class CrateStockTable < ActiveRecord::Migration
  def change
    create_table :stocks do |t|
      t.string :name
      t.string :code
      t.string :abc
      t.integer :stock_type
      t.string :industry_name
      t.string :tags

      t.timestamps
    end
  end
end
