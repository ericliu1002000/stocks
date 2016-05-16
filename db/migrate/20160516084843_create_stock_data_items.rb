class CreateStockDataItems < ActiveRecord::Migration
  def change
    create_table :stock_data_items do |t|
      t.integer :stock_data_item_id
      t.string :name
      t.string :category
      t.string :similar_name

      t.timestamps

    end
  end
end
