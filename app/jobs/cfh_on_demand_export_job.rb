require './lib/cfh_integration/demandware'

class CFHOnDemandExportJob < Struct.new(:cfh_exec_today, :cfh_exec_yesterday, :user_email, :sid)

  def perform
    puts 'On-Demand export job queued...'
    begin
      SalsifyToDemandware.export_on_demand_category_hierarchy(cfh_exec_today, sid)
      SalsifyToDemandware.roll_up_products(cfh_exec_today)

      puts 'generating on-demand trees...'
      tree_a_nodes = cfh_exec_today.salsify_sql_nodes.on_demand_nodes(sid)
      tree_b_nodes = cfh_exec_yesterday.salsify_sql_nodes.on_demand_nodes(sid)
      tree_a = SalsifyTree.new(tree_a_nodes, sid: sid)
      tree_b = SalsifyTree.new(tree_b_nodes, sid: sid)
    rescue SalsifyTree::MissingTreeRoot => error
      Bugsnag.notify(error)
    else
      puts 'generating on-demand diff...'
      diff = tree_a.on_demand_diff(tree_b)

      if diff.present?
        filename = "./tmp/#{sid}-#{Time.now.to_i}.xml"
        obj = Demandware::XMLGenerator.new(filename)
        obj.create_from_category_tree(diff)
        EmailNotifier.notify(cfh_on_demand_filename: filename, email: user_email, sid: sid, mode: :cfh_on_demand)
      else
        Bugsnag.notify('Salsify id not found in tree')
      end
    end
  end

end
