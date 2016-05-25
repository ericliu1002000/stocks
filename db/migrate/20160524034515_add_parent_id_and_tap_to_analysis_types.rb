class AddParentIdAndTapToAnalysisTypes < ActiveRecord::Migration
  def change
    add_column :analysis_types, :parent_id, :integer
    add_column :analysis_types, :tap, :integer
  end
end
