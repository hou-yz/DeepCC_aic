function removeWaiting(opts)
%REMOVEWAITING Summary of this function goes here
%   Detailed explanation goes here
colors = distinguishable_colors(5000);
for scene = opts.seqs{opts.sequence}
opts.current_scene = scene;
for iCam = opts.cams_in_scene{scene}
opts.current_camera = iCam;
tracker_output      = dlmread(fullfile(opts.experiment_root, opts.experiment_name, 'L2-trajectories', sprintf('cam%d_%s.txt',iCam, opts.sequence_names{opts.sequence})));
ids                 = unique(tracker_output(:,2));
frames              = min(tracker_output(:,1)):max(tracker_output(:,1));
to_remove = [];


%% traj data
traj_data  = cell(1,length(ids));
traj_speed = cell(1,length(ids));
for i = 1:length(ids)
    id = ids(i);
    id_data = tracker_output(tracker_output(:,2)==id,:);
    id_speed  = zeros(size(id_data,1),1);
    for j = 1:size(id_data,1)
        start_index   = max(1,j-4);
        end_index     = min(size(id_data,1),j);
        id_speed(j) = pdist2(id_data(end_index,7:8),id_data(start_index,7:8));
        id_speed(j) = id_speed(j)/(id_data(end_index,1)-id_data(start_index,1))*10;
    end
    traj_data{i}  = id_data;
    traj_speed{i} = [id_data(:,1),id_speed];
end

for i = 1:length(frames)
    %% all in frame
    frame    = frames(i);
    clc; fprintf('iCam: %d\n', iCam);
    fprintf('frame: %d\n', frame);
    line_ids = find(tracker_output(:,1)==frame);
    data     = tracker_output(line_ids,:);
    ids      = unique(data(:,2));
    if numel(ids) <= 1
        continue
    end
    speed = zeros(numel(ids),1);
    for j = 1:length(ids)
        id = ids(j);
        speed(j) = traj_speed{id}(traj_speed{id}(:,1)==frame,2);
    end
    bboxs = data(:,3:6);
    feets = feetPosition(bboxs);
    
    %% static in frame
    static_indices = find(speed < opts.static_speed);
    if sum(static_indices) == 0
        continue
    end
    % visualize
    if opts.visualize
        
        img  = opts.reader.getFrame(scene,iCam, frame-1);
        img_size    = size(img);
        
        positions   = bboxs;
        positions(:,1:2) = min(max(positions(:,1:2),1),img_size(2:-1:1)-1);
        positions(:,3:4) = max(min(positions(:,1:2)+positions(:,3:4),img_size(2:-1:1))-positions(:,1:2),1);
        
        
        if ~isempty(positions) && ~isempty(ids)
            img = insertObjectAnnotation(img,'rectangle', ...
                positions, ids,'TextBoxOpacity', 0.8, 'FontSize', 16, 'Color', 255*colors(ids,:) );
        end
        imshow(img)
    end
    static_feets       = feets(static_indices,:);
    [~,idx]            = sortrows(static_feets,2);
    static_indices     = static_indices(idx);
%     % the most close bbox to viewpoint
%     [~,closest_index]  = max(static_feets(:,2));
%     closest_index      = static_indices(closest_index);
% %     candidate_ids     = ids; candidate_ids(candidate_ids == closest_id) = [];
%     closest_bbox       = bboxs(closest_index,:);
    in = false(length(line_ids),1); 
    for j = 1:length(static_indices)
    static_index = static_indices(j);
    static_bbox  = bboxs(static_index,:);
    %% iou
%     ious         = bboxOverlapRatio(bboxs,static_bbox,'Min');
%     in(ious>0.5) = 1;
%     in(static_indices(j:end)) = 0;
    %% feet
    bbox_xv = [static_bbox(:,1),static_bbox(:,1)+static_bbox(:,3)]; 
    bbox_yv = [static_bbox(:,2),static_bbox(:,2)+static_bbox(:,4)];
    feet_xq = feets(:,1); feet_yq = feets(:,2);
    in = in + inpolygon(feet_xq,feet_yq,bbox_xv,bbox_yv);
    
    in(static_indices(j:end)) = 0;
    end
    in = logical(in);
    to_remove = [to_remove;line_ids(in)];
end
tracker_output(to_remove,:) = [];
dlmwrite(fullfile(opts.experiment_root, opts.experiment_name, 'L2-trajectories', sprintf('cam%d_%s_no_wait.txt',iCam, opts.sequence_names{opts.sequence})), ...
        tracker_output, 'delimiter', ' ', 'precision', 6);
end
end

end

