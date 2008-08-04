class CreateBlacklists < ActiveRecord::Migration
  def self.up
    create_table :blacklists do |t|
      t.string :domain

      t.timestamps
    end
  end

  def self.down
    drop_table :blacklists
  end
end
