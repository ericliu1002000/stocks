class AddEarlyBoundaryYearToAssessments < ActiveRecord::Migration
  def change
    add_column :assessments, :early_boundary_year, :integer
  end
end
