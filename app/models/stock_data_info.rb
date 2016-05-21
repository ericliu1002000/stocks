class StockDataInfo < ActiveRecord::Base
  belongs_to :stock_data_item
  belongs_to :stock
end