class CreateStockMarketHistories < ActiveRecord::Migration
  def change
    create_table :stock_market_histories do |t|
      t.integer :stock_id
      t.date :trade_date
      t.float :open_price
      t.float :peak_price
      t.float :close_price
      t.float :bottom_price
      t.integer :trade_volume
      t.integer :trade_ammount
      t.float :change_rate
      t.float :change_ammount
      t.float :amplitude_vibration

      t.timestamps
    end
    add_index :stock_market_histories, :stock_id
    add_index :stock_market_histories, :trade_date
  end
end
