class AddSortByToAnalysisTypes < ActiveRecord::Migration
  def change
    add_column :analysis_types, :sort_by, :integer
  end
end
