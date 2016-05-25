class CreateAssessments < ActiveRecord::Migration
  def change
    create_table :assessments do |t|
      t.integer :stock_id
      t.integer :base_on_year
      t.string :algorithm_name
      t.boolean :delete_flag

      t.timestamps null:false
    end
  end
end
