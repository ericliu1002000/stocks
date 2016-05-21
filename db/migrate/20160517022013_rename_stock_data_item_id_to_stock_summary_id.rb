class RenameStockDataItemIdToStockSummaryId < ActiveRecord::Migration
  def change
    rename_column :stock_data_items, :stock_data_item_id, :stock_summary_id
  end
end
