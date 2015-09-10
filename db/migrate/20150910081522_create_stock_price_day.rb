class CreateStockPriceDay < ActiveRecord::Migration
  def change
    create_table :stock_price_days do |t|
      t.string :code
      t.integer :top_price
      t.integer :low_price
      t.integer :start_price
      t.integer :end_price
      t.date :trading_day
      t.integer :stock_id

      t.index :stock_id
      t.index :trading_day
      t.index :code
      t.index :top_price
      t.index :low_price
    end
  end
end
