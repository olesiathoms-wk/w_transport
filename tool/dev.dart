// Copyright 2015 Workiva Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// import 'package:dart_dev/dart_dev.dart' show dev, config;
// import 'package:dart_dev/util.dart' show TaskProcess, reporter;
import 'package:args/command_runner.dart';
import 'package:dart_dev/configs/workiva.dart' as workiva_ddev_config;
import 'package:dart_dev/commands/dart_function_command.dart';
import 'package:dart_dev/commands/sequence_command.dart';
import 'package:dart_dev/commands/test_command.dart';
import 'package:dart_dev/commands/webdev_serve_command.dart';
import 'package:dart_dev/command_utils.dart';
import 'package:logging/logging.dart';

import 'server/server.dart' show Server;

// get config => (DdevBuilder()
//   ..addCommands(workiva_ddev_config.commands)
//   ..wrapCommand('test', ...)
// ).build();

List<Command<int>> get config => [
      ...workiva_ddev_config.build(
        // Rename and hide the default serve and test commands so that we can
        // provide custom wrapper commands that start the test servers first.
        serveConfig: WebdevServeConfig(
          commandName: '_serve',
          hidden: true,
          webdevServeArgs: ['example'],
        ),
        testConfig: TestConfig(commandName: '_test', hidden: true),
      ),

      // Wrap the serve command.
      SequenceCommand(
        SequenceConfig(
          commandName: 'serve',
          description: 'Serve the examples for this package.',
          beforeCommands: [
            ['test_server_start']
          ],
          primaryCommands: [
            ['_serve']
          ],
          afterCommands: [
            ['test_server_stop']
          ],
          helpCommand: ['_serve', '-h']
        ),
      ),

      // Configure unit and integration test commands and wrap them into a
      // single `test` command.
      TestCommand(
        TestConfig(
          commandName: 'test_unit',
          description: 'Run only the Dart unit tests.',
          testArgs: ['-P', 'unit'],
        ),
      ),
      TestCommand(
        TestConfig(
          commandName: '_test_integration',
          hidden: true,
          testArgs: ['-P', 'integration'],
        ),
      ),
      SequenceCommand(
        SequenceConfig(
          commandName: 'test_integration',
          description: 'Run only the Dart integration tests.',
          beforeCommands: [
            ['test_server_start']
          ],
          primaryCommands: [
            ['_test_integration']
          ],
          afterCommands: [
            ['test_server_stop']
          ],
        ),
      ),
      SequenceCommand(
        SequenceConfig(
          commandName: 'test',
          description: TestConfig.defaultDescription,
          primaryCommands: [
            ['test_unit'],
            ['test_integration']
          ],
        ),
      ),
      
      DartFunctionCommand(
        DartFunctionConfig(
          commandName: 'test_server_start',
          description: 'Starts the HTTP/WebSocket server for network tests.',
          function: startTestServers,
        ),
      ),
      DartFunctionCommand(
        DartFunctionConfig(
          commandName: 'test_server_stop',
          description: 'Starts the HTTP/WebSocket server for network tests.',
          function: stopTestServers,
          hidden: true,
        ),
      ),

      // TODO: copy-license
    ];

Server _dartTestServer;
final _dartTestServerLog = Logger('TestServer');
Process _sockjsTestServer;
final _sockjsTestServerLog = Logger('SockjsServer');

Future<int> startTestServers() async {
  await logTimedAsync(_dartTestServerLog, 'Starting HTTP/WS test server',
      () async {
    _dartTestServer = new Server();
    _dartTestServer.output.listen(_dartTestServerLog.fine);
    await _dartTestServer.start();
  });

  await logTimedAsync(_sockjsTestServerLog, 'Starting SockJS test server',
      () async {
    _sockjsTestServer = await Process.start('node', ['tool/server/sockjs.js'],
        mode: ProcessStartMode.detachedWithStdio);
    _sockjsTestServer.stdout
        .transform(utf8.decoder)
        .transform(LineSplitter())
        .listen(_sockjsTestServerLog.fine);
    _sockjsTestServer.stderr
        .transform(utf8.decoder)
        .transform(LineSplitter())
        .listen(_sockjsTestServerLog.fine);
  });

  // Wait a short amount of time to prevent the servers from missing anything.
  await Future.delayed(Duration(milliseconds: 500));

  return 0;
}

Future<int> stopTestServers() async {
  _sockjsTestServer?.kill();
  _sockjsTestServer = null;
  await _dartTestServer?.stop();
  _dartTestServer = null;

  return 0;
}
