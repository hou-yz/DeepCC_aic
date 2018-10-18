from __future__ import print_function
import argparse
import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
from torch.utils.data import DataLoader
from dataset import *
from sampler import *


class Net(nn.Module):
    def __init__(self, num_class=0):
        super(Net, self).__init__()
        self.num_class = num_class
        self.fc1 = nn.Linear(256 + 6, 1024)
        self.fc2 = nn.Linear(1024, 1024)
        self.fc3 = nn.Linear(1024, 128)
        if self.num_class > 0:
            self.out_layer = nn.Linear(128, self.num_class)

    def forward(self, x):
        out = self.fc1(x)
        out = F.relu(out)
        out = self.fc2(out)
        out = F.relu(out)
        out = self.fc3(out)
        out = F.relu(out)
        if self.num_class > 0:
            out = self.out_layer(out)
        return out


def train(args, model, train_loader, optimizer, epoch, criterion):
    model.train()
    for batch_idx in range(train_loader.dataset.num_spatialGroup):
        for _, (feat, pid, spaGrpID) in enumerate(train_loader):
            l = pid.shape[0]
            spaGrpID = np.unique(spaGrpID)
            data, target = feat.cuda(), pid.cuda()
            data = data.unsqueeze(0).expand(l, l, 262) - data.unsqueeze(1).expand(l, l, 262)
            target = (target.unsqueeze(0).expand(l, l) - target.unsqueeze(1).expand(l, l)) == 0
            data, target = data.view(-1, 262).float(), target.view(-1, 1).float()

            optimizer.zero_grad()
            output = model(data)
            loss = criterion(output, target)
            loss.backward()
            optimizer.step()
        if batch_idx % args.log_interval == 0:
            print('Train Epoch: {}, Batch:{},\tLoss: {:.6f}'.format(
                epoch, batch_idx, loss.item()))


def test(args, model, test_loader, criterion):
    model.eval()
    test_loss = 0
    correct = 0
    miss = 0
    lines = np.array([]).reshape(0, 2)
    if args.save_result:
        iCam = int(args.data_dir[-4])
    else:
        iCam = 0
    with torch.no_grad():
        for batch_idx in range(1, test_loader.dataset.num_spatialGroup + 1):
            for (feat, pid, spaGrpID) in test_loader:
                l = pid.shape[0]
                spaGrpID = np.unique(spaGrpID)
                data, target = feat.cuda(), pid.cuda()
                data = data.unsqueeze(0).expand(l, l, 262) - data.unsqueeze(1).expand(l, l, 262)
                target = (target.unsqueeze(0).expand(l, l) - target.unsqueeze(1).expand(l, l)) == 0
                data, target = data.view(-1, 262).float(), target.view(-1, 1).float()
                output = model(data)
                line = np.hstack((spaGrpID * np.ones(output.shape), output.cpu().numpy()))
                lines = np.vstack((lines, line))
                test_loss += criterion(output, target).item()  # sum up batch loss
                pred = output > 0.5  # get the index of the max log-probability
                correct += pred.eq(target.view_as(pred).byte()).sum().item()
                miss += target.shape[0] - pred.eq(target.view_as(pred).byte()).sum().item()
                pass
        print('\nTest set: Average loss: {:.4f}, Accuracy: {}/{} ({:.0f}%)\n'.
                      format(test_loss, correct, correct + miss, 100. * correct / (correct + miss)))

    if args.save_result:
        output_fname = osp.dirname(args.data_dir) + '/pairwise_dis_%d.h5' % iCam
        with h5py.File(output_fname, 'w') as f:
            mat_data = np.vstack(lines)
            f.create_dataset('dis', data=mat_data, dtype=float)
            pass


def main():
    # Training settings
    parser = argparse.ArgumentParser(description='PyTorch MNIST Example')
    parser.add_argument('--batch-size', type=int, default=256, metavar='N',
                        help='input batch size for training (default: 64)')
    parser.add_argument('--test-batch-size', type=int, default=256, metavar='N',
                        help='input batch size for training (default: 64)')
    parser.add_argument('--num-instances', type=int, default=16,
                        help="each minibatch consist of "
                             "(batch_size // num_instances) identities, and "
                             "each identity has num_instances instances, "
                             "default: 4")
    parser.add_argument('--epochs', type=int, default=10, metavar='N',
                        help='number of epochs to train (default: 10)')
    parser.add_argument('--lr', type=float, default=0.001, metavar='LR',
                        help='learning rate (default: 0.01)')
    parser.add_argument('--momentum', type=float, default=0.5, metavar='M',
                        help='SGD momentum (default: 0.5)')
    parser.add_argument('--train', action='store_true')
    parser.add_argument('--save_result', action='store_true')
    # parser.add_argument('--resume', type=str, default='', metavar='PATH')
    parser.add_argument('--data-dir', type=str, default='~/Data/DukeMTMC/ground_truth/hyperGT_trainval_mini.h5',
                        metavar='PATH')
    parser.add_argument('--seed', type=int, default=1, metavar='S',
                        help='random seed (default: 1)')
    parser.add_argument('--log-interval', type=int, default=100, metavar='N',
                        help='how many batches to wait before logging training status')
    args = parser.parse_args()

    torch.manual_seed(args.seed)

    dataset = HyperFeat(args.data_dir)
    train_loader = DataLoader(dataset, batch_size=args.batch_size,
                              sampler=RandomIdentitySampler(dataset, args.num_instances),
                              num_workers=0, pin_memory=True)

    test_loader = DataLoader(dataset, batch_size=args.test_batch_size,
                             sampler=RandomIdentitySampler(dataset, 10000),
                             num_workers=0, pin_memory=True)

    model = Net(num_class=1)
    model = nn.DataParallel(model).cuda()
    criterion = nn.L1Loss().cuda()
    optimizer = optim.SGD(model.parameters(), lr=args.lr, momentum=args.momentum)

    if args.train:
        for epoch in range(1, args.epochs + 1):
            train(args, model, train_loader, optimizer, epoch, criterion)
            # test(args, model, test_loader, criterion)
        torch.save({'state_dict': model.module.state_dict(), }, 'checkpoint.pth.tar')

    checkpoint = torch.load('checkpoint.pth.tar')
    model_dict = checkpoint['state_dict']
    model.module.load_state_dict(model_dict)
    test(args, model, test_loader, criterion)


if __name__ == '__main__':
    main()