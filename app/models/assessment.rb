class Assessment < ActiveRecord::Base
  belongs_to :stock
  has_many :assessment_items

  scope :valid, ->{where("delete_flag is null or delete_flag = 0")}
end
