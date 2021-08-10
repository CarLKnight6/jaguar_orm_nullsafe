import 'dart:async';
import 'package:jaguar_query/jaguar_query.dart';

/// The model
class Post {
  Post();

  Post.make({this.id, this.msg, this.author});

  int id;

  String msg;

  String author;

  String toString() => '$id $msg $author';
}

/// The bean
class PostBean extends Bean<Post> {
  /// Field DSL for id column
  final IntField id = IntField('_id');

  /// Field DSL for msg column
  final StrField msg = StrField('msg');

  /// Field DSL for author column
  final StrField author = StrField('author');

  Map<String, Field> _fields;
  Map<String, Field> get fields => _fields ??= {
        id.name: id,
        msg.name: msg,
        author.name: author,
      };

  PostBean(Adapter adapter) : super(adapter);

  @override
  List<SetColumn> toSetColumns(Post model,
      {bool update = false, Set<String> only}) {
    final ret = <SetColumn>[];

    ret.add(msg.set(model.msg));
    ret.add(author.set(model.author));

    return ret;
  }

  /// Table name for the model this bean manages
  String get tableName => 'posts';

  Post fromMap(Map map) {
    var post = Post();

    post.id = map['_id'];
    post.msg = map['msg'];
    post.author = map['author'];

    return post;
  }

  Future<void> createTable() async {
    await Create(tableName, ifNotExists: true)
        .addInt('_id', primary: true, autoIncrement: true)
        .addStr('msg')
        .addStr('author')
        .exec(adapter);
  }

  /// Inserts a new post into table
  Future<dynamic> insert(Post post) async {
    Insert st = inserter.setMany(toSetColumns(post)).id(id.name);
    return adapter.insert(st);
  }

  /// Updates a post
  Future<int> updateAuthor(int id, String author) async {
    Update updater = Update(tableName, where: this.id.eq(id));

    updater.set(this.author, author);

    return await adapter.update(updater);
  }

  /// Finds one post by [id]
  Future<Post> findById(int id) async {
    Find st = finder.where(this.id.eq(id));
    return findOne(st);
  }

  /// Deletes a post by [id]
  Future<int> remove(int id) async {
    Remove st = remover.where(this.id.eq(id));
    return adapter.remove(st);
  }
}
