class CreateStockDataInfos < ActiveRecord::Migration
  def change
    create_table :stock_data_infos do |t|
      t.integer :stock_id
      t.string :stock_code
      t.integer :stock_data_item_id
      t.string :quarterly_date
      t.integer :value
      t.string :monetary_unit
      t.string :source
      t.string :url, limit: 1000

      t.timestamps

    end
  end
end
