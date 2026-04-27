class StorySnapshot < ApplicationRecord
  belongs_to :story

  validates :score, :captured_at, presence: true
end
