class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :topic_subscriptions, dependent: :destroy
  has_many :subscribed_topics, through: :topic_subscriptions, source: :topic
  has_many :created_topics, class_name: "Topic", foreign_key: :created_by_id, dependent: :nullify
  has_many :push_subscriptions, dependent: :destroy
end
