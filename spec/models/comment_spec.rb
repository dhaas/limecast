require File.dirname(__FILE__) + '/../spec_helper'

describe Comment do
  before do
    @comment = Factory.create(:comment)
    @episode = @comment.episode
    @podcast = @episode.podcast
  end

  it 'should be modifiable if it is on the most recent episode of a podcast.' do
    @comment.should be_editable
  end

  it "shouldn't be modifiable if it is on an episode that isnt most recent." do
    Factory.create(:episode, :podcast => @podcast, :published_at => 20.days.from_now)

    # Original comment
    @comment.should_not be_editable
  end

  it 'should not be valid if there is no commenter' do
    Factory.build(:comment, :commenter => nil).should_not be_valid
  end
end

