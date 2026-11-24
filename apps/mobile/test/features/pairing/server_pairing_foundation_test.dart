import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirrorline/features/account/domain/account_models.dart';
import 'package:mirrorline/features/account/facade/account_token_store.dart';
import 'package:mirrorline/features/pairing/base/server_pairing_gateway.dart';
import 'package:mirrorline/features/pairing/base/server_pairing_idempotency_key_provider.dart';
import 'package:mirrorline/features/pairing/base/server_pairing_proof_signer.dart';
import 'package:mirrorline/features/pairing/base/server_pairing_transport.dart';
import 'package:mirrorline/features/pairing/domain/server_pairing_models.dart';
import 'package:mirrorline/features/pairing/facade/server_pairing_facade.dart';
import 'package:mirrorline/features/pairing/ui_service/server_pairing_controller.dart';
import 'package:mirrorline/features/sync/base/protocol_v1/protocol_crypto.dart';

void main() {
  final pairingContract = _pairingContractFixture();

  group('HTTP pairing contract', () {
    test('uses exact endpoints, bodies, and idempotency headers', () async {
      final transport = _Transport([
        _transaction(),
        _transaction(pairingId: _pairId2, role: 'SOURCE', state: 'redeemed'),
        _transaction(state: 'redeemed'),
        _transaction(state: 'proofs_verified'),
        _transaction(state: 'completed'),
        _transaction(state: 'cancelled'),
        const [
          {
            'deviceId': _sourceId,
            'role': 'SOURCE',
            'status': 'ACTIVE',
            'displayName': 'Source',
          },
        ],
        null,
      ]);
      final gateway = HttpServerPairingGateway(transport);

      await gateway.create('token', 'id-1');
      await gateway.redeem('token', _pairId2, 'ABCDEFGHJK', 'id-2');
      await gateway.status('token', _pairId);
      await gateway.submitProof('token', _pairId, 'signature', 'id-3');
      await gateway.confirmComparison('token', _pairId, true, 'id-4');
      await gateway.cancel('token', _pairId, 'id-5');
      await gateway.devices('token');
      await gateway.unpair('token', _sourceId, 'id-6');

      expect(
        transport.requests.map(
          (request) => '${request.method} ${request.path}',
        ),
        [
          'POST /v1/pairings',
          'POST /v1/pairings/$_pairId2/redeem',
          'GET /v1/pairings/$_pairId',
          'POST /v1/pairings/$_pairId/proofs',
          'POST /v1/pairings/$_pairId/comparison-confirmations',
          'DELETE /v1/pairings/$_pairId',
          'GET /v1/devices',
          'DELETE /v1/devices/$_sourceId',
        ],
      );
      expect(transport.requests[1].body, {'code': 'ABCDEFGHJK'});
      expect(transport.requests[3].body, {'signature': 'signature'});
      expect(transport.requests[4].body, {'matches': true});
      for (final index in [0, 1, 3, 4, 5, 7]) {
        expect(
          transport.requests[index].headers['Idempotency-Key'],
          'id-${[0, 1, 3, 4, 5, 7].indexOf(index) + 1}',
        );
      }
      expect(
        transport.requests[2].headers.containsKey('Idempotency-Key'),
        isFalse,
      );
      expect(
        transport.requests[6].headers.containsKey('Idempotency-Key'),
        isFalse,
      );
      expect(
        transport.requests.every(
          (request) => request.headers['Authorization'] == 'Bearer token',
        ),
        isTrue,
      );
    });

    test('secure idempotency keys are opaque and non-repeating', () {
      final provider = SecureServerPairingIdempotencyKeyProvider();
      final first = provider.next();
      final second = provider.next();
      expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(second, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(second, isNot(first));
    });

    test('rejects malformed path identifiers before reaching transport', () {
      final transport = _Transport([]);
      final gateway = HttpServerPairingGateway(transport);
      expect(
        () => gateway.unpair('token', '../../v1/pairings', 'id-1'),
        throwsA(isA<ServerPairingApiException>()),
      );
      expect(
        () => gateway.status('token', _alphaPairId.toUpperCase()),
        throwsA(isA<ServerPairingApiException>()),
      );
      expect(transport.requests, isEmpty);
    });
  });

  group('transfer and proof protocol', () {
    test('QR/manual data has an exact public allowlist', () {
      const transfer = PairingTransferPayload(
        pairingId: _pairId,
        code: 'ABCDEFGHJK',
        protocolVersion: 1,
      );
      final payload = transfer.toQrPayload();
      expect(payload.keys.toSet(), {'pairingId', 'code', 'protocolVersion'});
      expect(jsonEncode(payload), isNot(contains('expiresAt')));
      expect(jsonEncode(payload), isNot(contains('token')));
      expect(jsonEncode(payload), isNot(contains('key')));
      expect(PairingTransferPayload.fromQrPayload(payload).code, 'ABCDEFGHJK');
      expect(
        () => PairingTransferPayload.fromQrPayload({
          ...payload,
          'expiresAt': 'x',
        }),
        throwsFormatException,
      );
      expect(
        () => PairingTransferPayload.fromQrPayload({
          ...payload,
          'code': '123456',
        }),
        throwsFormatException,
      );
      for (final invalidId in [
        _alphaPairId.toUpperCase(),
        '00000000-0000-5000-8000-000000000001',
      ]) {
        expect(
          () => PairingTransferPayload.fromQrPayload({
            ...payload,
            'pairingId': invalidId,
          }),
          throwsFormatException,
        );
      }
      final authenticated = ServerPairingCodePayload(
        pairingId: _pairId,
        code: 'ABCDEFGHJK',
        protocolVersion: 1,
        expiresAt: _expiry,
      );
      expect(authenticated.expiresAt, _expiry);
      expect(authenticated.toQrPayload().containsKey('expiresAt'), isFalse);
    });

    test(
      'canonical transcript has exact v1 bytes and deterministic signature',
      () async {
        final transcript = _transcript(mainFingerprint: _seed7Fingerprint);
        final expected = utf8.encode(
          'mirrorline.pairing.v1\u0000'
          '{"challenge":"$_bytes32","main":{"deviceId":"$_mainId",'
          '"keyFingerprint":"$_seed7Fingerprint","keyVersion":1,"role":"MAIN",'
          '"userId":"$_userId"},"pairingId":"$_pairId",'
          '"protocolVersion":1,"source":{"deviceId":"$_sourceId",'
          '"keyFingerprint":"$_bytes32","keyVersion":2,"role":"SOURCE",'
          '"userId":"$_userId"}}',
        );
        expect(
          ProtocolCrypto.pairingTranscriptBytes(transcript.canonicalFields()),
          expected,
        );

        final key = await Ed25519().newKeyPairFromSeed(List<int>.filled(32, 7));
        final signer = Ed25519ServerPairingProofSigner(key);
        final signature = await signer.sign(transcript, ServerPairingRole.main);
        expect(
          signature,
          'X-CBFdEOmAawo7GEz1WPXGfLTNPBJ6l82v7zpHndqKHs6lIBZCqdU_jEvTJbau0o'
          'ObZfNZ1FShvt5sLRRHPYBw',
        );
        final publicKey = await key.extractPublicKey();
        expect(
          await Ed25519().verify(
            expected,
            signature: Signature(
              base64Url.decode('$signature=='),
              publicKey: publicKey,
            ),
          ),
          isTrue,
        );
      },
    );

    test(
      'proofs fail closed for missing or tampered transcript fields',
      () async {
        final key = await Ed25519().newKeyPairFromSeed(List<int>.filled(32, 7));
        final signer = Ed25519ServerPairingProofSigner(key);
        final missingFingerprint = PairingProofTranscript(
          pairingId: _pairId,
          challenge: _bytes32,
          protocolVersion: 1,
          main: const PairingCanonicalIdentity(
            userId: _userId,
            deviceId: _mainId,
            role: ServerPairingRole.main,
            keyVersion: 1,
            keyFingerprint: '',
          ),
          source: _transcript().source,
        );
        await expectLater(
          signer.sign(missingFingerprint, ServerPairingRole.main),
          throwsA(isA<ServerPairingApiException>()),
        );
        expect(
          _transcript().canonicalFields()['main'],
          containsPair('role', 'MAIN'),
        );
        await expectLater(
          signer.sign(_transcript(), ServerPairingRole.main),
          throwsA(isA<ServerPairingApiException>()),
        );
      },
    );
  });

  group('facade validation and failures', () {
    test('strictly parses the shared server pairing API v1 fixture', () async {
      final transactions = pairingContract['transactions'] as Map;
      final gateway = _Gateway()
        ..createResponse = _fixtureMap(transactions['created'])
        ..deviceRows = (pairingContract['devices'] as List)
            .map(_fixtureMap)
            .toList(growable: false);
      final facade = _facade(gateway, _Tokens());

      var transaction = _success(await facade.createMain());
      expect(transaction.code!.code, 'ABCDEFGHJK');
      for (final name in [
        'redeemed',
        'proofsVerified',
        'comparisonConfirmed',
        'completed',
        'expired',
        'cancelled',
        'rejected',
        'failed',
      ]) {
        gateway.statusResponse = _fixtureMap(transactions[name]);
        transaction = _success(await facade.refresh(transaction));
        expect(transaction.state.wireValue, transactions[name]['state']);
      }

      final devices = _success(await facade.devices());
      expect(devices.map((device) => device.status.wireValue), [
        'ACTIVE',
        'PENDING',
      ]);
      expect(
        devices
            .singleWhere((device) => device.role == ServerPairingRole.main)
            .createdAt
            .isUtc,
        isTrue,
      );
    });

    test('maps stable documented errors and clears stale sessions', () async {
      final cases = <String, ServerPairingFailureCode>{
        'PAIRING_NOT_FOUND': ServerPairingFailureCode.notFound,
        'PAIRING_CODE_INVALID': ServerPairingFailureCode.codeInvalid,
        'PAIRING_CODE_EXPIRED': ServerPairingFailureCode.codeExpired,
        'PAIRING_CODE_USED': ServerPairingFailureCode.codeUsed,
        'PAIRING_EXPIRED': ServerPairingFailureCode.codeExpired,
        'PAIRING_CANCELLED': ServerPairingFailureCode.stateInvalid,
        'PAIRING_REJECTED': ServerPairingFailureCode.stateInvalid,
        'PAIRING_FAILED': ServerPairingFailureCode.stateInvalid,
        'PAIRING_STATE_INVALID': ServerPairingFailureCode.stateInvalid,
        'PAIRING_PROOF_INVALID': ServerPairingFailureCode.proofInvalid,
        'PAIRING_COMPARISON_MISMATCH':
            ServerPairingFailureCode.comparisonMismatch,
        'DEVICE_LIMIT_REACHED': ServerPairingFailureCode.deviceLimitReached,
        'DEVICE_ROLE_CONFLICT': ServerPairingFailureCode.alreadyPaired,
        'AUTH_FORBIDDEN': ServerPairingFailureCode.forbidden,
        'RATE_LIMITED': ServerPairingFailureCode.rateLimited,
        'VALIDATION_FAILED': ServerPairingFailureCode.validation,
        'MALFORMED_RESPONSE': ServerPairingFailureCode.malformedResponse,
        'NETWORK_ERROR': ServerPairingFailureCode.unavailable,
        'SERVICE_UNAVAILABLE': ServerPairingFailureCode.unavailable,
      };
      for (final entry in cases.entries) {
        final gateway = _Gateway()..error = entry.key;
        final tokens = _Tokens();
        final result = await _facade(gateway, tokens).createMain();
        expect(_failureCode(result), entry.value, reason: entry.key);
        expect(tokens.cleared, isFalse);
      }
      for (final code in ['AUTH_SESSION_EXPIRED', 'DEVICE_REVOKED']) {
        final gateway = _Gateway()..error = code;
        final tokens = _Tokens();
        final result = await _facade(gateway, tokens).createMain();
        expect(_failureCode(result), ServerPairingFailureCode.sessionExpired);
        expect(tokens.cleared, isTrue);
      }
    });

    test(
      'rejects response identity, state, nested map, and capacity violations',
      () async {
        final invalid = <Map<String, Object?>>[
          _transaction(role: 'SOURCE'),
          _transaction(code: null),
          _transaction(code: 'INVALID'),
          _transaction(capacity: {'current': 0, 'max': 4}),
          _transaction(state: 'unknown'),
          _transaction(comparison: 'unexpected'),
          _transaction(capacity: {'current': 'zero', 'max': 5}),
          {..._transaction(), 'unexpected': true},
          {..._transaction(), 'expiresAt': '2030-01-01T00:00:00'},
          Map<String, Object?>.from(_transaction())..remove('comparisonValue'),
          Map<String, Object?>.from(_transaction())..remove('transcript'),
        ];
        for (final body in invalid) {
          final result = await _facade(
            _Gateway()..createResponse = body,
            _Tokens(),
          ).createMain();
          expect(
            _failureCode(result),
            ServerPairingFailureCode.malformedResponse,
          );
        }

        final expiresAtNow = await _facade(
          _Gateway()
            ..createResponse = {
              ..._transaction(),
              'expiresAt': DateTime.utc(2026).toIso8601String(),
            },
          _Tokens(),
        ).createMain();
        expect(
          _failureCode(expiresAtNow),
          ServerPairingFailureCode.codeExpired,
        );

        final mismatched = _transaction(
          pairingId: _pairId3,
          role: 'SOURCE',
          state: 'redeemed',
        );
        final redeem =
            await _facade(
              _Gateway()..redeemResponse = mismatched,
              _Tokens(),
            ).redeem(
              const PairingTransferPayload(
                pairingId: _pairId,
                code: 'ABCDEFGHJK',
                protocolVersion: 1,
              ),
            );
        expect(
          _failureCode(redeem),
          ServerPairingFailureCode.malformedResponse,
        );

        for (final brokenTranscript in [
          _transaction(
            role: 'SOURCE',
            state: 'redeemed',
            transcript: _transcriptMap(role: 'UNKNOWN'),
          ),
          _transaction(
            role: 'SOURCE',
            state: 'redeemed',
            transcript: _transcriptMap(sourceUser: _otherUserId),
          ),
          _transaction(
            role: 'SOURCE',
            state: 'redeemed',
            transcript: _transcriptMap(sourceDevice: _mainId),
          ),
          _transaction(
            role: 'SOURCE',
            state: 'redeemed',
            transcript: _transcriptMap(sourceVersion: 0),
          ),
          _transaction(
            role: 'SOURCE',
            state: 'redeemed',
            transcript: _transcriptMap(sourceFingerprint: ''),
          ),
          _transaction(
            role: 'SOURCE',
            state: 'redeemed',
            transcript: _transcriptMap(
              sourceFingerprint: '__________________________________________8=',
            ),
          ),
          _transaction(
            role: 'SOURCE',
            state: 'redeemed',
            transcript: {..._transcriptMap(), 'unexpected': true},
          ),
        ]) {
          final result =
              await _facade(
                _Gateway()..redeemResponse = brokenTranscript,
                _Tokens(),
              ).redeem(
                const PairingTransferPayload(
                  pairingId: _pairId,
                  code: 'ABCDEFGHJK',
                  protocolVersion: 1,
                ),
              );
          expect(
            _failureCode(result),
            ServerPairingFailureCode.malformedResponse,
          );
        }
      },
    );

    test(
      'unknown device role or status is malformed, not unavailable',
      () async {
        for (final device in [
          _device(role: 'OTHER'),
          <String, Object?>{'deviceId': 'source'},
        ]) {
          final result = await _facade(
            _Gateway()..deviceRows = [device],
            _Tokens(),
          ).devices();
          expect(
            _failureCode(result),
            ServerPairingFailureCode.malformedResponse,
          );
        }
      },
    );

    test('devices require a timezone-aware createdAt field', () async {
      for (final device in [
        Map<String, Object?>.from(_device())..remove('createdAt'),
        _device(createdAt: '2030-01-01T00:00:00'),
        {..._device(), 'unexpected': true},
      ]) {
        final result = await _facade(
          _Gateway()..deviceRows = [device],
          _Tokens(),
        ).devices();
        expect(
          _failureCode(result),
          ServerPairingFailureCode.malformedResponse,
        );
      }
    });

    test('API timestamps with offsets normalize to UTC', () async {
      final gateway = _Gateway()
        ..createResponse = {
          ..._transaction(),
          'expiresAt': '2030-01-01T08:00:00+08:00',
        }
        ..deviceRows = [_device(createdAt: '2030-01-01T08:00:00+08:00')];
      final facade = _facade(gateway, _Tokens());
      final transaction = _success(await facade.createMain());
      final device = _success(await facade.devices()).single;
      expect(transaction.expiresAt, DateTime.utc(2030));
      expect(transaction.expiresAt.isUtc, isTrue);
      expect(device.createdAt, DateTime.utc(2030));
      expect(device.createdAt.isUtc, isTrue);
    });

    test(
      'created responses reject a noncanonical authenticated device ID',
      () async {
        final result = await _facade(
          _Gateway(),
          _Tokens(deviceId: 'not-a-uuid'),
        ).createMain();
        expect(
          _failureCode(result),
          ServerPairingFailureCode.malformedResponse,
        );
      },
    );
  });

  group('facade and controller workflow', () {
    test(
      'status preserves a Main code only for its exact session expiry',
      () async {
        final gateway = _Gateway()
          ..createResponse = _transaction()
          ..statusResponse = _transaction(code: null);
        final facade = _facade(gateway, _Tokens());
        final created = _success(await facade.createMain());
        final refreshed = _success(await facade.refresh(created));
        expect(refreshed.code!.code, created.code!.code);

        gateway.statusResponse = {
          ..._transaction(code: null),
          'expiresAt': _expiry
              .add(const Duration(seconds: 1))
              .toIso8601String(),
        };
        expect(
          _failureCode(await facade.refresh(created)),
          ServerPairingFailureCode.malformedResponse,
        );
      },
    );

    test(
      'Main and Source complete only after server-confirmed completion',
      () async {
        final mainGateway = _Gateway()
          ..createResponse = _transaction()
          ..statusResponse = _transaction(state: 'redeemed')
          ..proofResponse = _transaction(state: 'proofs_verified')
          ..confirmationResponse = _transaction(state: 'completed');
        final main = _facade(mainGateway, _Tokens());
        final created = _success(await main.createMain());
        expect(created.state, ServerPairingState.created);
        final redeemed = _success(await main.refresh(created));
        expect(redeemed.state, ServerPairingState.redeemed);
        final proofs = _success(await main.submitProof(redeemed));
        expect(proofs.state, ServerPairingState.proofsVerified);
        expect(
          _success(await main.confirm(proofs, true)).state,
          ServerPairingState.completed,
        );

        final sourceGateway = _Gateway()
          ..redeemResponse = _transaction(role: 'SOURCE', state: 'redeemed')
          ..proofResponse = _transaction(
            role: 'SOURCE',
            state: 'proofs_verified',
          )
          ..confirmationResponse = _transaction(
            role: 'SOURCE',
            state: 'completed',
          );
        final source = _facade(sourceGateway, _Tokens(deviceId: _sourceId));
        final sourceRedeemed = _success(
          await source.redeem(
            const PairingTransferPayload(
              pairingId: _pairId,
              code: 'ABCDEFGHJK',
              protocolVersion: 1,
            ),
          ),
        );
        expect(sourceRedeemed.state, isNot(ServerPairingState.completed));
        final sourceProofs = _success(await source.submitProof(sourceRedeemed));
        expect(
          _success(await source.confirm(sourceProofs, true)).state,
          ServerPairingState.completed,
        );
      },
    );

    test(
      'proof submission binds the transcript to the authenticated device',
      () async {
        final gateway = _Gateway();
        final result = await _facade(
          gateway,
          _Tokens(deviceId: _sourceId),
        ).submitProof(_transactionModel(state: ServerPairingState.redeemed));
        expect(
          _failureCode(result),
          ServerPairingFailureCode.malformedResponse,
        );
      },
    );

    test(
      'refresh rejects a transcript for another authenticated device',
      () async {
        final gateway = _Gateway()
          ..statusResponse = _transaction(state: 'redeemed');
        final result = await _facade(
          gateway,
          _Tokens(deviceId: _sourceId),
        ).refresh(_transactionModel(state: ServerPairingState.created));
        expect(
          _failureCode(result),
          ServerPairingFailureCode.malformedResponse,
        );
      },
    );

    test(
      'cancel parses terminal transaction and recovery needs fresh transaction',
      () async {
        final gateway = _Gateway()
          ..createResponse = _transaction()
          ..cancelResponse = _transaction(state: 'cancelled');
        final controller = ServerPairingController(_facade(gateway, _Tokens()));
        await controller.createMain();
        final cancelled = _success(await controller.cancel());
        expect(cancelled.state, ServerPairingState.cancelled);
        expect(controller.state.phase, ServerPairingUiPhase.terminal);
        expect(
          await controller.recoverAsSource(
            const PairingTransferPayload(
              pairingId: _pairId,
              code: 'ABCDEFGHJK',
              protocolVersion: 1,
            ),
          ),
          isA<ServerPairingFailureResult<ServerPairingTransaction>>(),
        );
        gateway.redeemResponse = _transaction(
          pairingId: _pairId2,
          role: 'SOURCE',
          state: 'redeemed',
        );
        final sourceController = ServerPairingController(
          _facade(gateway, _Tokens(deviceId: _sourceId)),
        );
        sourceController.state = ServerPairingUiState(
          transaction: ServerPairingTransaction(
            pairingId: _pairId,
            state: ServerPairingState.cancelled,
            localRole: ServerPairingRole.source,
            expiresAt: _expiry,
            capacity: const PairingCapacity(current: 0, maximum: 5),
          ),
        );
        expect(
          _success(
            await sourceController.recoverAsSource(
              const PairingTransferPayload(
                pairingId: _pairId2,
                code: 'LMNPQRSTUV',
                protocolVersion: 1,
              ),
            ),
          ).pairingId,
          _pairId2,
        );
      },
    );

    test('controller exposes phases, capacity, and expiry inputs', () async {
      final gateway = _Gateway()
        ..createResponse = _transaction()
        ..proofResponse = _transaction(state: 'proofs_verified')
        ..confirmationResponse = _transaction(state: 'comparison_confirmed');
      final controller = ServerPairingController(_facade(gateway, _Tokens()));
      await controller.createMain();
      expect(controller.state.phase, ServerPairingUiPhase.awaitingSource);
      expect(controller.state.expiresAt, _expiry);
      controller.state = ServerPairingUiState(
        transaction: _transactionModel(state: ServerPairingState.redeemed),
      );
      await controller.submitProof();
      expect(controller.state.phase, ServerPairingUiPhase.comparisonRequired);
      expect(controller.state.transaction!.comparison, isNotNull);
      await controller.confirmComparison(true);
      expect(controller.state.phase, ServerPairingUiPhase.awaitingCompletion);

      final devices = _sourceDeviceIds
          .map((deviceId) => _device(deviceId: deviceId))
          .toList(growable: false);
      gateway.deviceRows = devices;
      final capacityController = ServerPairingController(
        _facade(gateway, _Tokens()),
      );
      await capacityController.loadDevices();
      expect(capacityController.state.availableCapacity, 0);
      expect(
        capacityController.state.phase,
        ServerPairingUiPhase.capacityLimited,
      );
    });

    test(
      'terminal states do not restart and errors select safe phases',
      () async {
        final gateway = _Gateway()..createResponse = _transaction();
        final controller = ServerPairingController(_facade(gateway, _Tokens()));
        controller.state = ServerPairingUiState(
          transaction: _transactionModel(state: ServerPairingState.completed),
        );
        expect(
          await controller.recoverAsMain(),
          isA<ServerPairingFailureResult>(),
        );
        gateway.error = 'DEVICE_ROLE_CONFLICT';
        await controller.createMain();
        expect(controller.state.phase, ServerPairingUiPhase.alreadyPaired);
        gateway.error = 'SERVICE_UNAVAILABLE';
        await controller.createMain();
        expect(controller.state.phase, ServerPairingUiPhase.unavailable);
      },
    );

    test(
      'rejected expired cancelled and failed responses remain terminal',
      () async {
        for (final state in [
          ServerPairingState.rejected,
          ServerPairingState.expired,
          ServerPairingState.cancelled,
          ServerPairingState.failed,
        ]) {
          final gateway = _Gateway()
            ..statusResponse = _transaction(state: state.wireValue);
          final controller = ServerPairingController(
            _facade(gateway, _Tokens()),
          );
          controller.state = ServerPairingUiState(
            transaction: _transactionModel(state: ServerPairingState.created),
          );
          final result = await controller.refresh();
          expect(
            result,
            isA<ServerPairingSuccess<ServerPairingTransaction>>(),
            reason:
                result is ServerPairingFailureResult<ServerPairingTransaction>
                ? '$state: ${result.failure.code}'
                : '$state: unexpected result',
          );
          expect(_success(result).state, state);
          expect(controller.state.phase, ServerPairingUiPhase.terminal);
          expect(await controller.recoverAsMain(), isA<ServerPairingSuccess>());
        }

        final mismatch = _Gateway()..error = 'PAIRING_COMPARISON_MISMATCH';
        final controller = ServerPairingController(
          _facade(mismatch, _Tokens()),
        );
        controller.state = ServerPairingUiState(
          transaction: _transactionModel(
            state: ServerPairingState.proofsVerified,
          ),
        );
        await controller.confirmComparison(false);
        expect(controller.state.phase, ServerPairingUiPhase.terminal);
      },
    );

    test(
      'generation isolation discards stale requests and old pairing responses',
      () async {
        final first = Completer<Map<String, Object?>>();
        final second = Completer<Map<String, Object?>>();
        var call = 0;
        final gateway = _Gateway()
          ..createHandler = () => ++call == 1 ? first.future : second.future;
        final controller = ServerPairingController(_facade(gateway, _Tokens()));
        final oldRequest = controller.createMain();
        final currentRequest = controller.createMain();
        second.complete(_transaction(pairingId: _pairId3));
        expect(_success(await currentRequest).pairingId, _pairId3);
        first.complete(_transaction(pairingId: _pairId4));
        expect(
          _failureCode(await oldRequest),
          ServerPairingFailureCode.staleTransaction,
        );
        expect(controller.state.transaction!.pairingId, _pairId3);
      },
    );

    test(
      'password reauth gates unpair and self-unpair clears saved tokens',
      () async {
        final tokens = _Tokens();
        final manager = _Manager();
        final reauth = _Reauth(false);
        final controller = ServerPairingController(
          _facade(_Gateway(), tokens, manager: manager, reauth: reauth),
        );
        controller.requestUnpair(_mainId);
        final denied = await controller.confirmUnpair('secret-password');
        expect(_failureCode(denied), ServerPairingFailureCode.forbidden);
        expect(manager.calls, isEmpty);
        expect(controller.state.toString(), isNot(contains('secret-password')));

        reauth.accept = true;
        controller.requestUnpair(_mainId);
        expect(
          await controller.confirmUnpair('secret-password'),
          isA<ServerPairingSuccess<void>>(),
        );
        expect(manager.calls, [_mainId]);
        expect(tokens.cleared, isTrue);
      },
    );

    test(
      'self-revoke loss clears a session that the server has revoked',
      () async {
        final tokens = _Tokens();
        final manager = _Manager()..error = 'AUTH_SESSION_EXPIRED';
        final controller = ServerPairingController(
          _facade(_Gateway(), tokens, manager: manager, reauth: _Reauth(true)),
        );
        controller.requestUnpair(_mainId);

        final result = await controller.confirmUnpair('secret-password');

        expect(_failureCode(result), ServerPairingFailureCode.sessionExpired);
        expect(tokens.cleared, isTrue);
        expect(manager.calls, [_mainId]);
      },
    );

    test('device capacity counts only active paired sources', () async {
      final gateway = _Gateway()
        ..deviceRows = [
          _device(deviceId: _sourceId, status: 'ACTIVE'),
          _device(deviceId: _sourceId2, status: 'PENDING'),
          _device(deviceId: _sourceId3, status: 'REVOKED'),
          _device(deviceId: _sourceId4, status: 'RETIRED'),
          _device(deviceId: _mainId, role: 'MAIN'),
        ];
      final controller = ServerPairingController(_facade(gateway, _Tokens()));
      await controller.loadDevices();
      expect(controller.state.availableCapacity, 4);
    });
  });

  test(
    'architecture keeps UI service out of base and server pairing out of LAN',
    () {
      final controller = File(
        'lib/features/pairing/ui_service/server_pairing_controller.dart',
      ).readAsStringSync();
      final gateway = File(
        'lib/features/pairing/base/server_pairing_gateway.dart',
      ).readAsStringSync();
      final facade = File(
        'lib/features/pairing/facade/server_pairing_facade.dart',
      ).readAsStringSync();
      expect(controller, isNot(contains('features/pairing/base')));
      expect(controller, contains('features/pairing/facade'));
      expect(controller, contains('features/pairing/domain'));
      expect('$gateway$facade'.toLowerCase(), isNot(contains('legacy')));
      expect('$gateway$facade'.toLowerCase(), isNot(contains('lan')));
      expect('$gateway$facade'.toLowerCase(), isNot(contains('socket')));
    },
  );
}

final _expiry = DateTime.utc(2030);
const _pairId = '00000000-0000-4000-8000-000000000001';
const _pairId2 = '00000000-0000-4000-8000-000000000005';
const _pairId3 = '00000000-0000-4000-8000-000000000006';
const _pairId4 = '00000000-0000-4000-8000-000000000007';
const _alphaPairId = 'abcdefab-cdef-4abc-8abc-abcdefabcdef';
const _userId = '00000000-0000-4000-8000-000000000002';
const _otherUserId = '00000000-0000-4000-8000-00000000000d';
const _mainId = '00000000-0000-4000-8000-000000000003';
const _sourceId = '00000000-0000-4000-8000-000000000004';
const _sourceId2 = '00000000-0000-4000-8000-000000000008';
const _sourceId3 = '00000000-0000-4000-8000-000000000009';
const _sourceId4 = '00000000-0000-4000-8000-00000000000a';
const _sourceId5 = '00000000-0000-4000-8000-00000000000b';
const _sourceId6 = '00000000-0000-4000-8000-00000000000c';
const _sourceDeviceIds = [
  _sourceId2,
  _sourceId3,
  _sourceId4,
  _sourceId5,
  _sourceId6,
];
const _bytes32 = '__________________________________________8';
const _seed7Fingerprint = '_oEsEvOrTOasXbaaw1L5BssbEe9D-zPiUu9_9VImOIk';

ServerPairingFacade _facade(
  _Gateway gateway,
  _Tokens tokens, {
  _Manager? manager,
  _Reauth? reauth,
}) => ServerPairingFacade(
  gateway: gateway,
  tokenStore: tokens,
  signer: _Signer(),
  idempotencyKeys: _FixedKeys(),
  deviceManager: manager,
  reauthenticator: reauth,
  clock: () => DateTime.utc(2026),
);

ServerPairingFailureCode _failureCode<T>(ServerPairingResult<T> result) =>
    (result as ServerPairingFailureResult<T>).failure.code;

T _success<T>(ServerPairingResult<T> result) =>
    (result as ServerPairingSuccess<T>).value;

Map<String, Object?> _fixtureMap(Object? value) =>
    Map<String, Object?>.from(value! as Map);

Map<String, dynamic> _pairingContractFixture() {
  var directory = Directory.current;
  while (directory.path != directory.parent.path) {
    final candidate = File(
      '${directory.path}/protocol-fixtures/pairing-api-v1.json',
    );
    if (candidate.existsSync()) {
      return jsonDecode(candidate.readAsStringSync()) as Map<String, dynamic>;
    }
    directory = directory.parent;
  }
  throw StateError('Unable to find the pairing API v1 fixture.');
}

PairingProofTranscript _transcript({String mainFingerprint = _bytes32}) =>
    PairingProofTranscript(
      pairingId: _pairId,
      challenge: _bytes32,
      protocolVersion: 1,
      main: PairingCanonicalIdentity(
        userId: _userId,
        deviceId: _mainId,
        role: ServerPairingRole.main,
        keyVersion: 1,
        keyFingerprint: mainFingerprint,
      ),
      source: const PairingCanonicalIdentity(
        userId: _userId,
        deviceId: _sourceId,
        role: ServerPairingRole.source,
        keyVersion: 2,
        keyFingerprint: _bytes32,
      ),
    );

Map<String, Object?> _transcriptMap({
  String pairingId = _pairId,
  String role = 'SOURCE',
  String sourceUser = _userId,
  String sourceDevice = _sourceId,
  int sourceVersion = 2,
  String sourceFingerprint = _bytes32,
}) => {
  'pairingId': pairingId,
  'challenge': _bytes32,
  'protocolVersion': 1,
  'main': {
    'userId': _userId,
    'deviceId': _mainId,
    'role': 'MAIN',
    'keyVersion': 1,
    'keyFingerprint': _bytes32,
  },
  'source': {
    'userId': sourceUser,
    'deviceId': sourceDevice,
    'role': role,
    'keyVersion': sourceVersion,
    'keyFingerprint': sourceFingerprint,
  },
};

Map<String, Object?> _transaction({
  String pairingId = _pairId,
  String role = 'MAIN',
  String state = 'created',
  Map<String, Object?>? capacity,
  Object? code = 'ABCDEFGHJK',
  Object? comparison,
  Map<String, Object?>? transcript,
}) {
  final requiresTranscript = {
    'redeemed',
    'proofs_verified',
    'comparison_confirmed',
    'completed',
    'rejected',
  }.contains(state);
  final requiresComparison = {
    'proofs_verified',
    'comparison_confirmed',
    'completed',
    'rejected',
  }.contains(state);
  final body = <String, Object?>{
    'pairingId': pairingId,
    'localRole': role,
    'state': state,
    'protocolVersion': 1,
    'expiresAt': _expiry.toIso8601String(),
    'capacity': capacity ?? {'current': 0, 'max': 5},
    'transcript': requiresTranscript
        ? transcript ?? _transcriptMap(pairingId: pairingId)
        : null,
    'comparisonValue': requiresComparison ? comparison ?? '123456' : comparison,
  };
  if (role == 'MAIN' && state == 'created' && code != null) {
    body['code'] = code;
  }
  return body;
}

ServerPairingTransaction _transactionModel({
  required ServerPairingState state,
}) => ServerPairingTransaction(
  pairingId: _pairId,
  state: state,
  localRole: ServerPairingRole.main,
  expiresAt: _expiry,
  capacity: const PairingCapacity(current: 0, maximum: 5),
  code: state == ServerPairingState.created
      ? ServerPairingCodePayload(
          pairingId: _pairId,
          code: 'ABCDEFGHJK',
          protocolVersion: 1,
          expiresAt: _expiry,
        )
      : null,
  comparison: state == ServerPairingState.proofsVerified
      ? const PairingComparisonValue('123456')
      : null,
  transcript: state == ServerPairingState.created || state.isTerminal
      ? null
      : _transcript(),
);

Map<String, Object?> _device({
  String deviceId = _sourceId,
  String role = 'SOURCE',
  String status = 'ACTIVE',
  String createdAt = '2030-01-01T00:00:00.000Z',
}) => {
  'deviceId': deviceId,
  'role': role,
  'status': status,
  'displayName': 'Device',
  'createdAt': createdAt,
};

class _Transport implements ServerPairingTransport {
  _Transport(this.responses);
  final List<Object?> responses;
  final requests = <ServerPairingHttpRequest>[];
  @override
  Future<ServerPairingHttpResponse> send(
    ServerPairingHttpRequest request,
  ) async {
    requests.add(request);
    return ServerPairingHttpResponse(
      statusCode: 200,
      body: responses.removeAt(0),
    );
  }
}

class _FixedKeys implements ServerPairingIdempotencyKeyProvider {
  var _value = 0;
  @override
  String next() => 'test-${++_value}';
}

class _Tokens implements AccountTokenStore {
  _Tokens({String deviceId = _mainId})
    : value = AccountTokenSet(
        accessToken: 'token',
        refreshToken: 'refresh',
        userId: _userId,
        deviceId: deviceId,
      );

  AccountTokenSet? value;
  bool cleared = false;
  @override
  Future<void> clear() async {
    cleared = true;
    value = null;
  }

  @override
  Future<AccountTokenSet?> read() async => value;
  @override
  Future<void> write(AccountTokenSet tokens) async => value = tokens;
}

class _Signer implements ServerPairingProofSigner {
  @override
  Future<String> sign(
    PairingProofTranscript transcript,
    ServerPairingRole localRole,
  ) async => 'signature';
}

class _Reauth implements ServerPairingReauthenticator {
  _Reauth(this.accept);
  bool accept;
  @override
  Future<bool> verifyCurrentPassword(String password) async => accept;
}

class _Manager implements ServerPairingDeviceManager {
  final calls = <String>[];
  String? error;
  @override
  Future<void> revokeDevice(String accessToken, String deviceId) async {
    calls.add(deviceId);
    if (error != null) throw ServerPairingApiException(error!);
  }
}

class _Gateway implements ServerPairingGateway {
  String? error;
  Map<String, Object?> createResponse = _transaction();
  Map<String, Object?> redeemResponse = _transaction(
    role: 'SOURCE',
    state: 'redeemed',
  );
  Map<String, Object?> statusResponse = _transaction();
  Map<String, Object?> proofResponse = _transaction(state: 'proofs_verified');
  Map<String, Object?> confirmationResponse = _transaction(state: 'completed');
  Map<String, Object?> cancelResponse = _transaction(state: 'cancelled');
  List<Map<String, Object?>> deviceRows = [];
  Future<Map<String, Object?>> Function()? createHandler;
  void _fail() {
    if (error != null) throw ServerPairingApiException(error!);
  }

  @override
  Future<Map<String, Object?>> create(
    String accessToken,
    String idempotencyKey,
  ) async {
    _fail();
    return createHandler?.call() ?? createResponse;
  }

  @override
  Future<Map<String, Object?>> redeem(
    String accessToken,
    String pairingId,
    String code,
    String idempotencyKey,
  ) async {
    _fail();
    return redeemResponse;
  }

  @override
  Future<Map<String, Object?>> status(
    String accessToken,
    String pairingId,
  ) async {
    _fail();
    return statusResponse;
  }

  @override
  Future<Map<String, Object?>> submitProof(
    String accessToken,
    String pairingId,
    String signature,
    String idempotencyKey,
  ) async {
    _fail();
    return proofResponse;
  }

  @override
  Future<Map<String, Object?>> confirmComparison(
    String accessToken,
    String pairingId,
    bool matches,
    String idempotencyKey,
  ) async {
    _fail();
    return confirmationResponse;
  }

  @override
  Future<Map<String, Object?>> cancel(
    String accessToken,
    String pairingId,
    String idempotencyKey,
  ) async {
    _fail();
    return cancelResponse;
  }

  @override
  Future<List<Map<String, Object?>>> devices(String accessToken) async {
    _fail();
    return deviceRows;
  }

  @override
  Future<void> unpair(
    String accessToken,
    String deviceId,
    String idempotencyKey,
  ) async => _fail();
}
