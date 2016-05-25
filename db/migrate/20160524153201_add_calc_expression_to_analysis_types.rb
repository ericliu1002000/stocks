class AddCalcExpressionToAnalysisTypes < ActiveRecord::Migration
  def change
    add_column :analysis_types, :calc_expression, :string
  end
end
