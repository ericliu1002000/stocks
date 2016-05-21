class ChangeValueOfStockDataInfo < ActiveRecord::Migration
  def change
    change_column :stock_data_infos, :value, :float
  end
end
