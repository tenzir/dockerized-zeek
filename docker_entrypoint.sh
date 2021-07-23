#!/bin/sh

# Make sure Zeek finds our custom scripts that ship with the Docker setup.
export ZEEKPATH="$(zeek-config --zeekpath):$ZEEK_SCRIPT_DIR"

# Obey if user provides custom command.
if [ "$#" != "0" ]; then
  echo executing user-provided command: $@ 1>&2
  exec "$@"
fi

# If we did not receive command line arguments, we assemble a Zeek command line
# according to the various tuning knobs exposed as environment variables and
# fixed mount points.

ZEEK="/opt/zeek/bin/zeek"

if [ -n "$ZEEK_DISABLE_CHECKSUMS" ]; then
  ZEEK="$ZEEK -C"
fi

# Read packets from trace or interface.
if [ -d /traces ]; then
  num_traces="$(find /traces -type f 2> /dev/null | wc -l | tr -d ' ')"
  if [ "$num_traces" = "0" ]; then
    echo 'no trace found in mounted /traces' 1>&2
    exit 1
  elif [ "$num_traces" = "1" ]; then
    # Optimization: no need to merge packets.
    ZEEK="$ZEEK -r /traces/*"
  else
    # We have more than one trace, so we merge them prior to running Zeek.
    ZEEK="ipsumdump -q --collate -w - /traces/* | $ZEEK -r -"
  fi
elif [ -n "$ZEEK_INTERFACE" ]; then
  # No traces provided, enter live mode if we have an interface.
  if ! getpcaps 1 | grep -q net_admin; then
    echo warning: no net_admin capability, run with --cap-add net-admin 1>&2
    cannot_drop_privileges=no
  fi
  if zeek -NN Zeek::AF_Packet > /dev/null 2>&1; then
    ZEEK="$ZEEK -i af_packet::$ZEEK_INTERFACE"
  else
    ZEEK="$ZEEK -i $ZEEK_INTERFACE"
  fi
else
  echo 'neither /traces nor $ZEEK_INTERFACE found' 1>&2
  exit 1
fi

# Append user-provided arguments.
if [ -n "$ZEEK_ARGS" ]; then
  ZEEK="$ZEEK $ZEEK_ARGS"
fi

# We disable filesystem logging if the user did not mount /logs.
if [ ! -d /logs ]; then
  # We only create /logs here just to have fixed working directory for Zeek.
  mkdir -p /logs
  chown zeek:zeek /logs
  # Disable actual logging. At this point we expect users to connect via Broker
  # as logger node and subscribe to the log topics of interest.
  echo disabling local logging, mount /logs to enable 1>&2
  ZEEK="$ZEEK Log::enable_local_logging=F"
fi

# It's available, but potentially unused.
cd /logs

# Append user-provided scripts.
if [ -n "$ZEEK_SCRIPTS" ]; then
  ZEEK="$ZEEK $ZEEK_SCRIPTS"
fi

# Drop privileges.
if [ -n "$cannot_drop_privileges" ]; then
  echo warning: cannot drop privileges, running as root 1>&2
else
  ZEEK="runuser -u zeek -- $ZEEK"
fi

# Go!
echo "executing command: $ZEEK" 1>&2
eval "$ZEEK"
