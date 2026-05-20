class GithubUser {
  final String login;
  final String? name;
  final String? avatarUrl;
  final int? id;

  const GithubUser({
    required this.login,
    this.name,
    this.avatarUrl,
    this.id,
  });

  factory GithubUser.fromJson(Map<String, dynamic> j) => GithubUser(
        login: (j['login'] as String?) ?? '',
        name: j['name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        id: j['id'] is int ? j['id'] as int : null,
      );

  Map<String, dynamic> toJson() => {
        'login': login,
        if (name != null) 'name': name,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (id != null) 'id': id,
      };
}
