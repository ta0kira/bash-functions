#!/usr/bin/env python

import argparse
import copy
import fcntl
import json
import os
import posixfile
import re
import select
import signal
import socket
import sys

# Global settings.

_termination_line = '82a98664-66ba-44db-9717-dda3631c7249'

_decay = 0.75

# TODO: Make these arguments.
_filename_pattern = os.path.expanduser('~/.hc_%s')
_socket_name = _filename_pattern % 'ipc'
_data_file = _filename_pattern % 'history'

_socket = None
_save_on_exit = None

# TODO: Protect this with a mutex.
class HistoryData(object):
  def __init__(self, filename=None):
    self._filename = filename
    self._params = { 't': 0 }
    self._all_data = {}

  def FindData(self, patterns):
    # NOTE: Returns tuple (i, line).
    regexes = tuple(re.compile(pattern) for pattern in patterns)
    matches = filter(lambda l: any(r.search(l[0]) for r in regexes), self._all_data.iteritems())
    # Update scores so that they're all for the current time.
    for match in matches:
      match[1]['score_now'] = match[1]['score'] * _decay**(self._params['t']-match[1]['t'])
    def _ExtractMatch((l,m)):
      return (m['t'], l)
    return tuple(_ExtractMatch(m) for m in sorted(matches, key=lambda m: m[1]['score_now'], reverse=True))

  def AppendData(self, data):
    for line in data:
      self._params['t'] = self._params['t'] + 1
      if line not in self._all_data:
        self._all_data[line] = { 'score': 1.0, 't': self._params['t'] }
      else:
        old = self._all_data[line]
        self._all_data[line] = { 'score': 1.0 + old['score'] * _decay**(self._params['t']-old['t']), 't': self._params['t'] }

  def DeleteData(self, indices):
    indices = set(indices)
    self._all_data = dict(filter(lambda l: l[1]['t'] not in indices, self._all_data.iteritems()))

  def SaveData(self, filename=None):
    if not filename:
      filename = self._filename
    try:
      output_data = { 'params': self._params, 'all_data': self._all_data }
      with open(filename, 'w') as data:
        json.dump(output_data, data, indent=2, sort_keys=True)
    except (OSError, IOError) as e:
      print >> sys.stderr, 'Error: %s' % e

  def RestoreData(self, filename=None):
    if not filename:
      filename = self._filename
    try:
      with open(filename, 'r') as data:
        input_data = json.load(data)
      if 'params' in input_data:
        self._params = input_data['params']
      if 'all_data' in input_data:
        self._all_data = input_data['all_data']
    except (OSError, IOError) as e:
      print >> sys.stderr, 'Error: %s' % e


all_modes = []

def RegisterMode(func):
  global all_modes
  all_modes.append(func.__name__)
  return func

class CommandProcessor(object):

  def __init__(self, *args, **kwds):
    self._history_data = HistoryData(*args, **kwds)

  def Execute(self, mode, conn):
    return getattr(self, mode)(conn)

  @RegisterMode
  def read(self, conn):
    patterns = GetLinesHelper(conn)
    if not patterns:
      patterns = ['.']
    for match in self._history_data.FindData(patterns):
      print >> conn, '%s %s' % match
    conn.flush()

  @RegisterMode
  def write(self, conn):
    self._history_data.AppendData(GetLinesHelper(conn))

  @RegisterMode
  def delete(self, conn):
    try:
      indices = set(int(i) for i in GetLinesHelper(conn))
    except ValueError as e:
      print >> sys.stderr, 'Error: %s' % e
    self._history_data.DeleteData(indices)

  @RegisterMode
  def save(self, conn=None):
    filename = None
    if conn is not None:
      name = ReadlineHelper(conn).rstrip('\n\r')
      if name and name != _termination_line:
        filename = name
    self._history_data.SaveData(filename)

  @RegisterMode
  def restore(self, conn=None):
    filename = None
    if conn is not None:
      name = ReadlineHelper(conn).rstrip('\n\r')
      if name and name != _termination_line:
        filename = name
    self._history_data.RestoreData(filename)

# Helpers.

def ExitCleanup(sig=None, frame=None):
  if sig is not None:
    signal.signal(sig, signal.SIG_DFL)
  try:
    os.remove(_socket_name)
  except Exception as e:
    print >> sys.stderr, 'Error: %s' % e
  if _save_on_exit:
    _save_on_exit()
  os.kill(0, sig)

def HandleConnection(command_processor):
  try:
    socket_obj, _ = _socket.accept()
    fcntl.fcntl(socket_obj.fileno(), fcntl.F_SETFL,
                fcntl.fcntl(socket_obj.fileno(), fcntl.F_GETFL) | os.O_NONBLOCK)
    conn = socket_obj.makefile('a+')
    # Wait for input data to be present.
    r, _, _, = select.select([conn], [], [], 1.0)
    if not r:
      return
    header = ReadlineHelper(conn).strip()
    mode = ReadlineHelper(conn).strip()
    print >> sys.stderr, 'Executing %s: %s' % (mode, header)
    try:
      command_processor.Execute(mode, conn)
      print >> conn, _termination_line
    except Exception as e:
      print >> sys.stderr, 'Error: %s' % e
  except socket.error:
    pass
  finally:
    try:
      conn.close()
      socket_obj.close()
    except UnboundLocalError:
      pass

def GetLinesHelper(conn):
  lines = []
  while True:
    line = ReadlineHelper(conn)
    if not line:
      break
    line = line.rstrip('\n\r')
    if line == _termination_line:
      break
    lines.append(line)
  return lines

def ReadlineHelper(conn,tries=1,delay=0.01):
  line = ''
  for i in xrange(tries):
    line = conn.readline()
    if line or i == tries - 1:
      break
    r, _, _, = select.select([conn], [], [], delay)
  return line

def ListModes():
  mode_pattern = re.compile('Process_(.+)')
  modes = []
  for f in globals().keys():
    match = mode_pattern.match(f)
    if match:
      modes.append(match.group(1))
  return tuple(modes)

def CreateSocket():
  global _socket
  _socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
  _socket.bind(_socket_name)
  # NOTE: This is a race condition.
  os.chmod(_socket_name, 0600)
  _socket.listen(10)

# Daemon mode.

def RunDaemon():
  global _save_on_exit
  try:
    command_processor = CommandProcessor(_data_file)
    # Execute cleanup for these signals.
    for sig in ('SIGHUP', 'SIGINT', 'SIGTERM', 'SIGQUIT'):
      signal.signal(getattr(signal, sig), ExitCleanup)
    # Ignore these signals.
    for sig in ('SIGPIPE',):
      signal.signal(getattr(signal, sig), signal.SIG_IGN)
    # Setup.
    CreateSocket()
    command_processor.restore()
    _save_on_exit = command_processor.save
    # Process input.
    while True:
      HandleConnection(command_processor)

  finally:
    ExitCleanup()

# CLI mode.

def RunCLI(mode):
  cached_lines = sys.stdin.readlines()
  try:
    socket_obj = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    socket_obj.connect(_socket_name)
    conn = socket_obj.makefile('a+')
    try:
      print >> conn, os.getpid()
      print >> conn, mode
      conn.flush()
      for line in cached_lines:
        print >> conn, line,
      print >> conn, _termination_line
      conn.flush()
    except socket.error:
      print >> sys.stderr, 'Error contacting daemon.'
      exit(1)
    error = True
    while True:
      line = conn.readline()
      if not line:
        break
      line = line.rstrip('\n\r')
      if line == _termination_line:
        error = False
        break
      print >> sys.stdout, line
    if error:
      print >> sys.stderr, 'Failed to execute %s.' % mode
      exit(1)
  finally:
    socket_obj.close()

# Execution.

def GetArgs():
  parser = argparse.ArgumentParser(description='History Collector Daemon and CLI')
  parser.add_argument('--mode', type=str, required=True,
                      choices=('daemon',) + tuple(all_modes))
  return parser.parse_args()

if __name__ == '__main__':
  args = GetArgs()
  if args.mode == 'daemon':
    RunDaemon()
  else:
    RunCLI(args.mode)
