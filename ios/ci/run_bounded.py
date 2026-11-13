#!/usr/bin/env python3
"""Bound a CI command and let the runner publish its logs even when a child stalls."""
import argparse
import os
import signal
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--seconds', type=float, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if args.seconds <= 0 or not command:
        parser.error('A positive timeout and command are required.')
    process = subprocess.Popen(command, start_new_session=True)
    try:
        return process.wait(timeout=args.seconds)
    except subprocess.TimeoutExpired:
        print(f'CI command exceeded {args.seconds:g} seconds; stopping its process group.', file=sys.stderr, flush=True)
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        return 124


if __name__ == '__main__':
    sys.exit(main())
