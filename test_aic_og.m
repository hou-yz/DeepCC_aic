clear
clc

%% Options
opts = get_opts_aic();
opts.experiment_name = 'aic_og';
% opts.detections = 'yolo3';
% basis setting for DeepCC
opts.tracklets.window_width = 10;
opts.trajectories.window_width = 30;
opts.trajectories.overlap = 15;
opts.identities.window_width = 1000;
% correlation threshold setting according to `view_distance_distribution(opts)`
% opts.feature_dir = 'det_features_zju_best_test_ssd';
% opts.tracklets.threshold    = 7;
% opts.trajectories.threshold = 7;
% opts.identities.threshold   = 7;
% opts.tracklets.diff_p    = 2.14;
% opts.trajectories.diff_p = 2.14;
% opts.identities.diff_p   = 2.14;
% opts.tracklets.diff_n    = 2.14;
% opts.trajectories.diff_n = 2.14;
% opts.identities.diff_n   = 2.14;

opts.feature_dir = 'det_features_ide_basis_train_10fps_lr_5e-2_ssd512_test';
opts.tracklets.threshold    = 10;
opts.trajectories.threshold = 10;
opts.identities.threshold   = 10;
opts.tracklets.diff_p    = 7.66;
opts.trajectories.diff_p = 7.66;
opts.identities.diff_p   = 7.66;
opts.tracklets.diff_n    = 7.66;
opts.trajectories.diff_n = 7.66;
opts.identities.diff_n   = 7.66;


% alpha
% opts.tracklets.alpha    = 1;
% opts.trajectories.alpha = 1;
% opts.identities.alpha   = 1;

create_experiment_dir(opts);

%% Setup Gurobi
if ~exist('setup_done','var')
    setup;
    setup_done = true;
end

%% Run Tracker
% opts.visualize = true;
opts.sequence = 6;
opts.scene_by_icam = [1, 1, 1, 1, 1, 2, 2, 2, 2, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5];


%% Tracklets
opts.tracklets.spatial_groups = 0;
opts.optimization = 'KL';
compute_L1_tracklets_aic(opts);

%% Single-camera trajectories
% weights
opts.trajectories.weightSmoothness = 1;
opts.trajectories.weightVelocityChange = 0.01;
% opts.trajectories.weightDistance = 0.01;
% opts.trajectories.weightShapeChange = 1;
opts.trajectories.weightIOU = 0.5;

opts.optimization = 'KL';
%opts.trajectories.use_indiff = false;
opts.experiment_name = 'aic_og';
opts.trajectories.appearance_groups = 1;
compute_L2_trajectories_aic(opts);

%% Multi-camera identities
% weights
% opts.identities.weightSmoothness = 1;

% opts.optimization = 'BIPCC';
opts.identities.optimal_filter = false;
opts.identities.consecutive_icam_matrix = ones(40);
opts.identities.reintro_time_matrix = ones(1,40)*inf;
opts.identities.appearance_groups = 0;
compute_L3_identities_aic(opts);

prepareMOTChallengeSubmission_aic;

