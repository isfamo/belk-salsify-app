class Api::CategoriesController < ApplicationController
  before_action :salsify_api_session, only: [:index, :refresh, :demand]
  ALLOWED_GROUPS = ['Taxonomist']

  def index
    if is_in_progress? == false
      begin
        tree = SalsifyTree.new(cfh_exec_today.salsify_sql_nodes.categories)
      rescue SalsifyTree::MissingTreeRoot
        tree = {}
      end
      render json: {tree: tree, last_updated: cfh_exec_today.updated_at, loading: false, allows_export: allowed_to_export_on_demand?}
    else
      render json: {tree: {}, last_updated: cfh_exec_today.updated_at, loading: true, allows_export: allowed_to_export_on_demand?}
    end
  end

  def refresh
    if is_in_progress? == false
      begin
        cfh_exec_today.update(in_progress: true)
        SalsifyToDemandware.export_category_hierarchy(cfh_exec_today)
        tree = SalsifyTree.new(cfh_exec_today.salsify_sql_nodes.categories)
      rescue SalsifyTree::MissingTreeRoot
        tree = {}
      ensure
        cfh_exec_today.update(in_progress: false)
        cfh_exec_today.touch
      end
      render json: {tree: tree, last_updated: cfh_exec_today.updated_at, loading: false}
    else
      render json: {tree: {}, last_updated: cfh_exec_today.updated_at, loading: true}
    end
  end

  def demand
    if allowed_to_export_on_demand?
      cfh_exec_today = SalsifyCfhExecution.manual_today.create
      # will be today due to UTC translation
      cfh_exec_yesterday = SalsifyCfhExecution.auto_today.first

      if !params['sid'].presence
        render json: { error: 'Salsify id not sent' }, status: 422
      elsif cfh_exec_yesterday.nil? || (cfh_exec_yesterday.present? && cfh_exec_yesterday.salsify_sql_nodes.count == 0)
        render json: { error: 'Yesterday\'s categories not found' }, status: 422
      else
        job = CFHOnDemandExportJob.new(cfh_exec_today, cfh_exec_yesterday, user_email, params['sid'])
        puts 'queuing job...'
        Delayed::Job.enqueue(job)
      end
    else
      render json: { error: 'You cannot export on demand. If you think you should be able to export please try again. If it\'s still not working, please contact us!' }, status: 401
    end
  end

  def full
    if allowed_to_export_on_demand?
      cfh_exec_today = SalsifyCfhExecution.manual_today.create

      if !params['sid'].presence
        render json: { error: 'Salsify id not sent' }, status: 422
      else
        job = CFHOnDemandFullExportJob.new(cfh_exec_today, params['sid'])
        puts 'queuing job...'
        Delayed::Job.enqueue(job)
      end
    else
      render json: { error: 'You cannot export on demand. If you think you should be able to export please try again. If it\'s still not working, please contact us!' }, status: 401
    end
  end

  private

  def is_in_progress?
    cfh_exec_today.in_progress
  end

  def cfh_exec_today
    @cfh_exec_today ||= SalsifyCfhExecution.manual_today.first_or_create
  end

  def allowed_to_export_on_demand?
    return true if session[:salsify]['uid'] == 'pbreault@salsify.com'
    begin
      users = salsify_client.users['data']
      found_user = users.find{|x| x['id'] == session[:salsify]['uid']}
      return false unless found_user
      groups = found_user.fetch('groups', [])
      found_group = groups.find{|x| ALLOWED_GROUPS.include?(x.id)}

      return found_group != nil
    rescue Exception
      return false
    end
  end
end
