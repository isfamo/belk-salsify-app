workers Integer(ENV['NUM_WORKERS'] || 1)
# queues((ENV['QUEUES'] || ENV['QUEUE'] || '').split(','))
# sleep_delay ENV['WORKER_SLEEP_DELAY']

# This is a hack so we can tell we're running in the master process before any children
# have been forked

preload_app

# This runs in the master process after the app has been preloaded
after_preload_app do
  # Don't hang on to Postgres connections from the master after we've completed initialization
  ActiveRecord::Base.connection_pool.disconnect!
end

# This runs in the worker processes after it has been forked
on_worker_boot do
  connection_config = ActiveRecord::Base.connection_config
  ActiveRecord::Base.establish_connection(connection_config)
end
