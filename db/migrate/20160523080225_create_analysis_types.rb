class CreateAnalysisTypes < ActiveRecord::Migration
  def change
    create_table :analysis_types do |t|
      t.string :name
      t.boolean :with_year
      t.boolean :is_used

      t.timestamps null:false
    end
  end
end
