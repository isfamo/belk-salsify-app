class Api::JobStatusesController < ApplicationController
  before_action :salsify_api_session, only: [ :index ]

  def index
    render json: {
      cma_job: JobStatus.cma_job.try(:serializable_hash),
      cfh_job: JobStatus.cfh_job.try(:serializable_hash),
      offline_cfh_job: JobStatus.offline_cfh_job.try(:serializable_hash),
      color_job: JobStatus.color_job.try(:serializable_hash),
      inventory: JobStatus.inventory.try(:serializable_hash),
      dwre_master: JobStatus.dwre_master.try(:serializable_hash),
      dwre_limited: JobStatus.dwre_limited.try(:serializable_hash)
    }
  end

end
