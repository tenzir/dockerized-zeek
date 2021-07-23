# This script executes by default when starting the Docker container.

@load base/frameworks/broker

redef Site::local_nets += { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 };

# Enable peers to connect via Broker and subscribe to Zeek-internal
# communication, e.g., to register as logger node.
event zeek_init()
  {
  Broker::listen(Broker::default_listen_address, Broker::default_port,
                 Broker::default_listen_retry);
  }
