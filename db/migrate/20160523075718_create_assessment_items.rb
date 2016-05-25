class CreateAssessmentItems < ActiveRecord::Migration
  def change
    create_table :assessment_items do |t|
      t.integer :assessment_id
      t.integer :year
      t.integer :analysis_type_id
      t.float :value
      t.string :money_unit

      t.timestamps null:false
    end
  end
end
