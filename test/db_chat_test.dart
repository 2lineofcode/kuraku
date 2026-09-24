import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:javit/app/data/database/_init_db.dart';
import 'package:javit/app/data/database/_update_db.dart';
import 'package:javit/app/data/database/db_chat.dart';
import 'package:javit/app/data/models/chat_entity.dart';

import 'chat_test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);
  test('Chat schema persists messages, preserves drafts, enforces constraints and cascades deletion', () async {
    final db = ChatTestDatabase();
    Get.put<DBService>(ChatTestService()..dbMain = db);
    await DBUpdate.onUpgrade(db, 7, DBUpdate.version);
    final chat = ChatConversation()..draft = 'Unsent text';
    await DBChat.saveConversation(chat);
    final first = await DBChat.send(chat, 'Hello');
    chat.messages.add(first);
    final second = await DBChat.send(chat, 'Second message');
    chat.messages.add(second);
    expect(second.position, 2);
    final activity = chat.lastActivityAt;
    chat.draft = 'Next draft';
    await DBChat.saveConversation(chat);
    await DBChat.rename(chat, 'Renamed chat');
    expect(chat.lastActivityAt, activity);
    expect((await DBChat.getConversations()).single.draft, 'Next draft');
    expect((await DBChat.getMessages(chat.id)).map((message) => message.content), ['Hello', 'Second message']);
    db.failMessageInsert = true;
    await expectLater(DBChat.send(chat, 'Must not be saved'), throwsStateError);
    expect(chat.draft, 'Next draft');
    expect((await DBChat.getConversations()).single.draft, 'Next draft');
    expect((await DBChat.getMessages(chat.id)).length, 2);
    db.failMessageInsert = false;
    await DBChat.saveTranslation('雨の散歩', 'Jalan saat hujan');
    await DBChat.saveTranslation('雨の散歩', 'Berjalan di tengah hujan');
    expect(await DBChat.getTranslation('雨の散歩'), 'Berjalan di tengah hujan');
    final statements = List<List<Object?>>.from(db.statements);
    await DBChat.recoverInterrupted(db);
    final recovery = db.statements.last;
    await DBChat.delete(chat.id);
    final deletion = db.statements.last;
    expect(await DBChat.getMessages(chat.id), isEmpty);
    final result = await Process.run('python3', ['-c', r'''
import json, os, sqlite3, sys, tempfile
schema, statements, recovery, deletion, chat_id = json.loads(sys.argv[1])
with tempfile.TemporaryDirectory() as folder:
    path = os.path.join(folder, 'chat.db')
    conn = sqlite3.connect(path)
    conn.execute('PRAGMA foreign_keys = ON')
    conn.execute('CREATE TABLE existing_data (value TEXT)')
    conn.execute("INSERT INTO existing_data VALUES ('preserved')")
    for sql in schema:
        if 'ADD COLUMN activity' not in sql or not any(row[1] == 'activity' for row in conn.execute('PRAGMA table_info(chat_message)')):
            conn.execute(sql)
    for sql, args in statements:
        conn.execute(sql, args)
    conn.commit()
    conn.close()
    conn = sqlite3.connect(path)
    conn.execute('PRAGMA foreign_keys = ON')
    assert conn.execute("SELECT translated_text FROM chat_translation WHERE source_text = '雨の散歩' AND target_language = 'id'").fetchall() == [('Berjalan di tengah hujan',)]
    assert conn.execute('SELECT title, draft FROM chat_conversation').fetchone() == ('Renamed chat', 'Next draft')
    assert conn.execute('SELECT content FROM chat_message ORDER BY position').fetchall() == [('Hello',), ('Second message',)]
    for sql in schema:
        if 'ADD COLUMN activity' not in sql or not any(row[1] == 'activity' for row in conn.execute('PRAGMA table_info(chat_message)')):
            conn.execute(sql)
    assert conn.execute('SELECT value FROM existing_data').fetchone() == ('preserved',)
    def invalid(sql, args):
        try:
            conn.execute(sql, args)
        except sqlite3.IntegrityError:
            return
        raise AssertionError('Constraint not enforced')
    insert = 'INSERT INTO chat_message (id, conversation_id, position, role, content, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
    for parent, position, role, status in [(chat_id, 1, 'user', 'completed'), (chat_id, 0, 'user', 'completed'), ('missing', 3, 'user', 'completed'), (chat_id, 3, 'invalid', 'completed'), (chat_id, 3, 'user', 'invalid')]:
        invalid(insert, ['bad', parent, position, role, '', status, 'now', 'now'])
    invalid('UPDATE chat_conversation SET title = ? WHERE id = ?', ['  ', chat_id])
    conn.execute(insert, ['partial', chat_id, 3, 'assistant', 'Partial reply', 'streaming', 'now', 'now'])
    conn.execute(*recovery)
    assert conn.execute("SELECT content, status FROM chat_message WHERE id = 'partial'").fetchone() == ('Partial reply', 'failed')
    conn.commit()
    # A failed message insert must not clear the saved draft.
    try:
        with conn:
            conn.execute("UPDATE chat_conversation SET draft = '' WHERE id = ?", [chat_id])
            conn.execute(insert, ['duplicate', chat_id, 1, 'user', 'text', 'completed', 'now', 'now'])
    except sqlite3.IntegrityError:
        pass
    assert conn.execute('SELECT draft FROM chat_conversation').fetchone() == ('Next draft',)
    conn.execute(*deletion)
    assert conn.execute('SELECT count(*) FROM chat_message').fetchone()[0] == 0
    assert conn.execute('SELECT value FROM existing_data').fetchone() == ('preserved',)
    conn.close()
''', jsonEncode([db.schema, statements, recovery, deletion, chat.id])]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
