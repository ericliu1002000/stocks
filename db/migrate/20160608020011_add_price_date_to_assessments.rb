class AddPriceDateToAssessments < ActiveRecord::Migration
  def change
    add_column :assessments, :price_date, :date
  end
end
