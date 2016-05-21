class CreateStockSummaries < ActiveRecord::Migration
  def change
    create_table :stock_summaries do |t|
      t.string :name

      t.timestamps
    end
  end
end
