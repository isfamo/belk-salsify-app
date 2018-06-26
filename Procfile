web: bundle exec puma -C config/puma.rb
worker: bundle exec delayed_job_worker_pool ./config/delayed_job_worker_pool.rb
cars_daemon: bundle exec rake cars:automated_pim_import
ads_daemon: bundle exec rake rrd:automated_ads_import
delayed_job_alert_daemon: bundle exec rake cars:delayed_job_alert_daemon calm_interval=180 alert_interval=3600 warning_threshold=1000
dw_daemon: bundle exec rake demandware:daemon
