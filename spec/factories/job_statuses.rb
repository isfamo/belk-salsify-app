FactoryGirl.define do
  factory :completed_job, class: JobStatus do
    title 'cma'
    status 'complete'
    start_time { 10.minutes.ago }
    end_time { Time.now }
  end

  factory :in_progress_job, class: JobStatus do
    title 'cma'
    start_time { 10.minutes.ago }
  end

end
