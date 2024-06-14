import 'dart:convert';
import 'dart:ui';

import 'package:checks/checks.dart';
import 'package:test/scaffolding.dart';
import 'package:zulip/api/model/model.dart';

import '../../example_data.dart' as eg;
import '../../stdlib_checks.dart';
import '../../widgets/stream_colors_checks.dart';
import 'model_checks.dart';

void main() {
  test('CustomProfileFieldChoiceDataItem', () {
    const input = '''{
      "0": {"text": "Option 0", "order": 1},
      "1": {"text": "Option 1", "order": 2},
      "2": {"text": "Option 2", "order": 3}
    }''';
    final decoded = jsonDecode(input) as Map<String, dynamic>;
    final choices = CustomProfileFieldChoiceDataItem.parseFieldDataChoices(decoded);
    check(choices).jsonEquals({
      '0': const CustomProfileFieldChoiceDataItem(text: 'Option 0'),
      '1': const CustomProfileFieldChoiceDataItem(text: 'Option 1'),
      '2': const CustomProfileFieldChoiceDataItem(text: 'Option 2'),
    });
  });

  group('User', () {
    final Map<String, dynamic> baseJson = Map.unmodifiable({
      'user_id': 123,
      'delivery_email': 'name@example.com',
      'email': 'name@example.com',
      'full_name': 'A User',
      'date_joined': '2023-04-28',
      'is_active': true,
      'is_owner': false,
      'is_admin': false,
      'is_guest': false,
      'is_billing_admin': false,
      'is_bot': false,
      'role': 400,
      'timezone': 'UTC',
      'avatar_version': 0,
      'profile_data': <String, dynamic>{},
    });

    User mkUser(Map<String, dynamic> specialJson) {
      return User.fromJson({ ...baseJson, ...specialJson });
    }

    test('delivery_email', () {
      check(mkUser({'delivery_email': 'name@email.com'}).deliveryEmailStaleDoNotUse)
        .equals('name@email.com');
    });

    test('profile_data', () {
      check(mkUser({'profile_data': <String, dynamic>{}}).profileData).isNull();
      check(mkUser({'profile_data': null}).profileData).isNull();
      check(mkUser({'profile_data': {'1': {'value': 'foo'}}}).profileData)
        .isNotNull().keys.single.equals(1);
    });

    test('is_system_bot', () {
      check(mkUser({}).isSystemBot).isFalse();
      check(mkUser({'is_cross_realm_bot': true}).isSystemBot).isTrue();
      check(mkUser({'is_system_bot': true}).isSystemBot).isTrue();
    });
  });

  group('ZulipStream.canRemoveSubscribersGroup', () {
    final Map<String, dynamic> baseJson = Map.unmodifiable({
      'stream_id': 123,
      'name': 'A stream',
      'description': 'A description',
      'rendered_description': '<p>A description</p>',
      'date_created': 1686774898,
      'first_message_id': null,
      'invite_only': false,
      'is_web_public': false,
      'history_public_to_subscribers': true,
      'message_retention_days': null,
      'stream_post_policy': StreamPostPolicy.any.apiValue,
      // 'can_remove_subscribers_group': null,
      'stream_weekly_traffic': null,
    });

    test('smoke', () {
      check(ZulipStream.fromJson({ ...baseJson,
        'can_remove_subscribers_group': 123,
      })).canRemoveSubscribersGroup.equals(123);
    });

    // TODO(server-8): field renamed in FL 197
    test('support old can_remove_subscribers_group_id', () {
      check(ZulipStream.fromJson({ ...baseJson,
        'can_remove_subscribers_group_id': 456,
      })).canRemoveSubscribersGroup.equals(456);
    });

    // TODO(server-6): field added in FL 142
    test('support field missing', () {
      check(ZulipStream.fromJson({ ...baseJson,
      })).canRemoveSubscribersGroup.isNull();
    });
  });

  group('Subscription', () {
    test('converts color to int', () {
      Subscription subWithColor(String color) {
        return Subscription.fromJson(
          deepToJson(eg.subscription(eg.stream())) as Map<String, dynamic>
            ..['color'] = color,
        );
      }
      check(subWithColor('#e79ab5').color).equals(0xffe79ab5);
      check(subWithColor('#ffffff').color).equals(0xffffffff);
      check(subWithColor('#000000').color).equals(0xff000000);
    });

    test('colorSwatch caching', () {
      final sub = eg.subscription(eg.stream(), color: 0xffffffff);
      check(sub.debugCachedSwatchValue).isNull();
      sub.colorSwatch();
      check(sub.debugCachedSwatchValue).isNotNull().base.equals(const Color(0xffffffff));
      sub.color = 0xffff0000;
      check(sub.debugCachedSwatchValue).isNull();
      sub.colorSwatch();
      check(sub.debugCachedSwatchValue).isNotNull().base.equals(const Color(0xffff0000));
    });
  });

  group('Message', () {
    Map<String, dynamic> baseStreamJson() =>
      deepToJson(eg.streamMessage()) as Map<String, dynamic>;

    test('subject -> topic', () {
      check(baseStreamJson()).not((it) => it.containsKey('topic'));
      check(Message.fromJson(baseStreamJson()
        ..['subject'] = 'hello'
      )).topic.equals('hello');
    });

    test('match_subject -> matchTopic', () {
      check(baseStreamJson()).not((it) => it.containsKey('match_topic'));
      check(Message.fromJson(baseStreamJson()
        ..['match_subject'] = 'yo'
      )).matchTopic.equals('yo');
    });

    test('no crash on unrecognized flag', () {
      final m1 = Message.fromJson(
        (deepToJson(eg.streamMessage()) as Map<String, dynamic>)
          ..['flags'] = ['read', 'something_unknown'],
      );
      check(m1).flags.deepEquals([MessageFlag.read, MessageFlag.unknown]);

      final m2 = Message.fromJson(
        (deepToJson(eg.dmMessage(from: eg.selfUser, to: [eg.otherUser])) as Map<String, dynamic>)
          ..['flags'] = ['read', 'something_unknown'],
      );
      check(m2).flags.deepEquals([MessageFlag.read, MessageFlag.unknown]);
    });
  });

  group('DmMessage', () {
    final Map<String, dynamic> baseJson = Map.unmodifiable(deepToJson(
      eg.dmMessage(from: eg.otherUser, to: [eg.selfUser]),
    ) as Map<String, dynamic>);

    DmMessage parse(Map<String, dynamic> specialJson) {
      return DmMessage.fromJson({ ...baseJson, ...specialJson });
    }

    Iterable<DmRecipient> asRecipients(Iterable<User> users) {
      return users.map((u) =>
        DmRecipient(id: u.userId, email: u.email, fullName: u.fullName));
    }

    Map<String, dynamic> withRecipients(Iterable<User> recipients) {
      final from = recipients.first;
      return {
        'sender_id': from.userId,
        'sender_email': from.email,
        'sender_full_name': from.fullName,
        'display_recipient': asRecipients(recipients).map((r) => r.toJson()).toList(),
      };
    }

    User user2 = eg.user(userId: 2);
    User user3 = eg.user(userId: 3);
    User user11 = eg.user(userId: 11);

    test('displayRecipient', () {
      check(parse(withRecipients([user2])).displayRecipient)
        .deepEquals(asRecipients([user2]));

      check(parse(withRecipients([user2, user3])).displayRecipient)
        .deepEquals(asRecipients([user2, user3]));
      check(parse(withRecipients([user3, user2])).displayRecipient)
        .deepEquals(asRecipients([user2, user3]));

      check(parse(withRecipients([user2, user3, user11])).displayRecipient)
        .deepEquals(asRecipients([user2, user3, user11]));
      check(parse(withRecipients([user3, user11, user2])).displayRecipient)
        .deepEquals(asRecipients([user2, user3, user11]));
      check(parse(withRecipients([user11, user2, user3])).displayRecipient)
        .deepEquals(asRecipients([user2, user3, user11]));
    });

    test('allRecipientIds', () {
      check(parse(withRecipients([user2])).allRecipientIds)
        .deepEquals([2]);

      check(parse(withRecipients([user2, user3])).allRecipientIds)
        .deepEquals([2, 3]);
      check(parse(withRecipients([user3, user2])).allRecipientIds)
        .deepEquals([2, 3]);

      check(parse(withRecipients([user2, user3, user11])).allRecipientIds)
        .deepEquals([2, 3, 11]);
      check(parse(withRecipients([user3, user11, user2])).allRecipientIds)
        .deepEquals([2, 3, 11]);
      check(parse(withRecipients([user11, user2, user3])).allRecipientIds)
        .deepEquals([2, 3, 11]);
    });
  });
}
