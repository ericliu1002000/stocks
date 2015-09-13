class AddTuijianPriceToStock < ActiveRecord::Migration
  def change
    add_column :stocks, :tuijian_high_price, :integer
    add_column :stocks, :tuijian_low_price, :integer
    add_column :stock_price_days, :year, :integer
    add_column :stock_price_days, :jidu, :integer
    add_index :stock_price_days, :year
    add_index :stock_price_days, :jidu
  end
end
