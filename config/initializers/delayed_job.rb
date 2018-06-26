Delayed::Worker.logger = Rails.logger
Delayed::Worker.max_attempts = 2
Delayed::Worker.raise_signal_exceptions = :term
Delayed::Worker.default_queue_name = 'default'
