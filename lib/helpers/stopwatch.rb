class Stopwatch

  def initialize(job_name)
    @job_name = job_name
    @start = Time.now
  end

  def self.time(job_name = nil)
    stopwatch = Stopwatch.new(job_name)
    puts "#{job_name}..."
    response = yield
    stopwatch.stop
    response
  end

  def stop
    @end = Time.now
    puts "#{@job_name} completed in #{minutes} minutes..."
  end

  def time
    @end.nil? ? Time.now - @start : @end - @start
  end

  def minutes
    time / 60.0
  end

end
