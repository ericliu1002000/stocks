class CrateStockTable < ActiveRecord::Migration
  def change
    create_table :stocks do |t|
      t.string :name
      t.string :code
      t.integer :current_price
      t.integer :ten_years_top
      t.integer :ten_years_low
      t.integer :buy_price, :default => 200
      t.string :status, :default => 'unknow'
      t.timestamps
      t.string :city_name
    end
  end
end
