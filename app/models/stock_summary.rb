class StockSummary < ActiveRecord::Base
  has_many :stock_data_items
end