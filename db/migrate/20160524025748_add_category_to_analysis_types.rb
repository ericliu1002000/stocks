class AddCategoryToAnalysisTypes < ActiveRecord::Migration
  def change
    add_column :analysis_types, :category, :string
  end
end
