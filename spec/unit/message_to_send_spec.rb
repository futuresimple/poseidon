require 'spec_helper'

RSpec.describe MessageToSend do
  it "provides access to topic,value,key" do
    mts = MessageToSend.new("hello_topic", "Hello World", "key")
    expect(mts.topic).to eq("hello_topic")
    expect(mts.value).to eq("Hello World")
    expect(mts.key).to eq("key")
  end

  it "encodes messages to ascii" do
    checkmark = "\u2713".encode('utf-8')
    mts = MessageToSend.new("hello_topic", checkmark, "key")
    expect(mts.value.encoding).to eq(Encoding::ASCII_8BIT)
  end
end
