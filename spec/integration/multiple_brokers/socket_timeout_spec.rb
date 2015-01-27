require 'integration/multiple_brokers/spec_helper'
require 'timeout'

RSpec.describe "blocked port", :requires => :sudo_pfctl do
  let(:topic) { "test" }
  let(:cluster_metadata) { ClusterMetadata.new }
  let(:message) { MessageToSend.new(topic, "dupa") }
  let(:socket_timeout_ms) { 100 }
  let(:producer_opts) {{
      :required_acks => 1,
      :socket_timeout_ms => socket_timeout_ms,
  }}

  before(:each) do
    # enable & reset firewall
    Pfctl.enable_pfctl
    Pfctl.unblock_ports

    @zookeeper = ZookeeperRunner.new
    @brokers = (9092..9093).map { |port| BrokerRunner.new(port - 9092, port, 1, 2) }
    @zookeeper.start
    @brokers.each(&:start)
    sleep 2

    # autocreate the topic by asking for information about it
    c = Connection.new("localhost", 9092, "metadata_fetcher", 10_000)
    md = c.topic_metadata([topic])
    spec_sleep 1, "creating topic"
  end

  after(:each) do
    Pfctl.unblock_ports

    @brokers.each(&:stop)
    @zookeeper.stop
    spec_sleep 2, "waiting for cluster and ZK to stop"
  end

  it "socket_timeout effective when port is blocked" do
    blocked_broker = block_leader("localhost:9092", cluster_metadata)

    expect {
      Timeout::timeout(5*socket_timeout_ms / 1000.0) {
        prod = Producer.new([broker_string(blocked_broker)], topic, producer_opts)
        prod.send_messages([message])
      }
    }.to raise_error(Poseidon::Errors::UnableToFetchMetadata)
  end

  it "reconnects to slave within timeout when leader is blocked" do
    blocked_broker = block_leader("localhost:9092", cluster_metadata)
    not_blocked_broker = not_blocked(cluster_metadata.brokers, blocked_broker)
    brokers = [broker_string(blocked_broker), broker_string(not_blocked_broker)]

    Timeout::timeout(5*socket_timeout_ms / 1000.0) {
      prod = Producer.new(brokers, topic, producer_opts)
      prod.send_messages([message])
    }

    pc = PartitionConsumer.new("test_client", not_blocked_broker.host, not_blocked_broker.port,
                                topic, 0, :earliest_offset, {:socket_timeout_ms => 100})
    res = pc.fetch

    expect(res.first.value).to eq message.value
  end
end
