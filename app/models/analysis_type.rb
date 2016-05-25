class AnalysisType < ActiveRecord::Base
  scope :used, -> {where is_used: true}
  scope :with_year, -> {where with_year: true}
  scope :without_year, ->{where with_year: false}
end
