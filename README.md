<h1 align="center">
  Dockerized Zeek
</h1>
<div align="center">
  
**A flexible Docker distribution of the [Zeek][zeek] network monitor.**

[![Chat][chat-badge]][chat-url]
[![License][license-badge]][license-url]
</div>

## Usage

This [Zeek][zeek] Docker setup supports both live and trace-based monitoring.
The following environment variables control the runtime behavior of Zeek:

- `$ZEEK_SCRIPT_DIR`: a directory with custom scripts. It is added to
  `$ZEEKPATH` so that you can load scripts directly (by adjusting
  `$ZEEK_SCRIPTS` below) without needing to specify an absolute path.

- `$ZEEK_ARGS`: additional command-line arguments to append to the Zeek
  invocation, before loading scripts.

- `$ZEEK_SCRIPTS`: the set of loaded scripts, after `$ZEEK_ARGS`.

- `$ZEEK_DISABLE_CHECKSUMS`: appends `-C` to invocation to disable computation
  of IP checksums. Set this variable to a non-empty string when Zeek
  unvoluntarily skips packets.

- `$ZEEK_INTERFACE`: the name of the interface to read packets from.

The following mount points control the behavior of this container:

- `/logs`: when mounted, Zeek will write logs into this directory.

  When not mounted, Zeek disables logging to the local file system. You can
  still use log shipping via Broker (see below).

- `/traces`: when mounted, Zeek will analyze all traces in this directory. The
  directory must not be empty, otherwise the container exits prematurely. Every
  file in the directory must be a valid PCAP trace.

  When not mounted, Zeek will listen on interface `$ZEEK_INTERFACE`, or on
  `af_packet::$ZEEK_INTERFACE` when the AF_PACKET plugin is installed (which is
  the default).

### Analyze a PCAP file

To perform a one-shot Zeek run over a given trace file, mount a volume
with PCAP traces to `/traces` and a directory for logs to `/logs`.

```sh
docker run -it -v pcap-dir:/traces -v log-dir:/logs zeek
```

This only works if `/traces` contains at least one trace. If the directory
contains multiple traces, `ipsumdump` concatenates the packets from all traces
and sorts them by their PCAP packet timestamp prior to shoving them into Zeek.
If `/traces` is empty or is not mounted, Zeek attempts to analyze live traffic
(see below).

### Analyze live traffic

To analyze packets on an interface, simply do not mount `/traces`.

To capture packets on an interface on the host, pass `--network host` to the
invocation. Zeek listens on the interface from the environment variable
`ZEEK_INTERFACE` (default: `eth0`):

```sh
docker run -it -v log-dir:/logs --network host --cap-add net-admin zeek
```

The runtime attempts drops privileges to user `zeek` (via `runuser`) before
running `zeek`. If you do not pass `--cap-add net-admin`, then the `zeek`
process will run as root.

The image will transparently use the `AF_PACKET` plugin for `$ZEEK_INTERFACE` if
available, i.e., prefix `$ZEEK_INTERFACE` with `af_packet::`.

A small annoyance for testing: `--network host` doesn't work with Docker
Desktop for Mac.

### Execute custom scripts

You can easily provide custom scripts by mounting a script directory to
`$ZEEK_SCRIPT_DIR` (default: `/zeek`). The directory will be added to
`$ZEEKPATH` such that you load scripts simply by adding the filename to the
environment variable `$ZEEK_SCRIPTS`.

Say you have a file `magic.zeek` in a local directoy `analysis`. You can load
it as follows:

```sh
docker run -it -v my-scripts:/zeek -e ZEEK_SCRIPTS=magic --network host zeek
```

Note that this overrides the default value of `$ZEEK_SCRIPTS`.

### Enabling log shipping via Broker

This Docker image makes it possible to avoid writing logs to disk and ship them
to a third party via Broker instead. This feature is always available,
regardless of whether you mounted `/logs`. But it comes in particularly handy
*without* mounting `/logs` so that Zeek can be seen as a side-effect-free
function streaming logs.

How does it work? Zeek comes with out-of-the-box functionality to ship logs via
Broker. Clusterized setups already operate this way, where the master node
opens a TCP socket and waits for Broker peers to connect, and then to subscribe
to events.

This Docker setup doesn't run in cluster mode, but instead executes `zeek`
binary right away. (In the future, it will use the [Supervisor
framework](https://docs.zeek.org/en/master/frameworks/supervisor.html).) The
[docker-entrypoint script](scripts/docker-entrypoint.zeek) enables the Broker
connection so that clients can connect. In particular, subscribing to the topic
`zeek/logs` allows for tapping into the full feed of logs. Zeek logger nodes
consume log events this way and then write them out to their local disk. But
third-party applications, such as [VAST](https://github.com/tenzir/vast), can
consume this log stream as well.

## Development

To build the Docker image, run `docker build` from the repository root as
follows:

```sh
docker build -t zeek .
```

You can select a specific Zeek version by adjusting the `ZEEK_VERSION` build
argument. Both Zeek 3.x and 4.x work:

```sh
docker build -t zeek --build-arg ZEEK_VERSION=3.2.4-0 .
```

For the Zeek 4.x series, you can also choose a long-term support (LTS) version
by setting `ZEEK_LTS`:

```sh
docker build -t zeek --build-arg ZEEK_LTS=1 .
```

<p align="center">
  Developed with ❤️ by <strong><a href="https://tenzir.com">Tenzir</a></strong>
</p>

[zeek]: https://www.zeek.org
[chat-badge]: https://img.shields.io/badge/Slack-Tenzir%20Community%20Chat-brightgreen?logo=slack&color=purple&style=flat
[chat-url]: http://slack.tenzir.com
[license-badge]: https://img.shields.io/badge/license-BSD-blue.svg
[license-url]: https://raw.github.com/vast-io/vast/master/COPYING
