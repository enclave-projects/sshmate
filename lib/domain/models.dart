// Copyright 2026 SSH Mate contributors
// SPDX-License-Identifier: GPL-3.0-only

class Host {
  Host({
    required this.id,
    required this.label,
    required this.address,
    this.port = 22,
    this.username = 'root',
    this.group = '',
    List<String> tags = const [],
    this.identityId,
    this.notes = '',
    this.favorite = false,
  }) : tags = List.unmodifiable(tags);
  final String id, label, address, username, group, notes;
  final int port;
  final List<String> tags;
  final String? identityId;
  final bool favorite;
  Host copyWith({
    String? label,
    String? address,
    int? port,
    String? username,
    String? group,
    List<String>? tags,
    String? identityId,
    String? notes,
    bool? favorite,
  }) => Host(
    id: id,
    label: label ?? this.label,
    address: address ?? this.address,
    port: port ?? this.port,
    username: username ?? this.username,
    group: group ?? this.group,
    tags: tags ?? this.tags,
    identityId: identityId ?? this.identityId,
    notes: notes ?? this.notes,
    favorite: favorite ?? this.favorite,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'address': address,
    'port': port,
    'username': username,
    'group': group,
    'tags': tags,
    'identityId': identityId,
    'notes': notes,
    'favorite': favorite,
  };
  factory Host.fromJson(Map<String, dynamic> j) => Host(
    id: j['id'],
    label: j['label'],
    address: j['address'],
    port: j['port'] ?? 22,
    username: j['username'] ?? 'root',
    group: j['group'] ?? '',
    tags: List<String>.from(j['tags'] ?? []),
    identityId: j['identityId'],
    notes: j['notes'] ?? '',
    favorite: j['favorite'] ?? false,
  );
}

class Identity {
  const Identity({
    required this.id,
    required this.label,
    this.username = '',
    this.privateKey = '',
    this.passphrase = '',
    this.password = '',
  });
  final String id, label, username, privateKey, passphrase, password;
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'username': username,
    'privateKey': privateKey,
    'passphrase': passphrase,
    'password': password,
  };
  factory Identity.fromJson(Map<String, dynamic> j) => Identity(
    id: j['id'],
    label: j['label'],
    username: j['username'] ?? '',
    privateKey: j['privateKey'] ?? '',
    passphrase: j['passphrase'] ?? '',
    password: j['password'] ?? '',
  );
}

class Snippet {
  const Snippet({required this.id, required this.label, required this.command});
  final String id, label, command;
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'command': command,
  };
  factory Snippet.fromJson(Map<String, dynamic> j) =>
      Snippet(id: j['id'], label: j['label'], command: j['command']);
}

class ForwardRule {
  const ForwardRule({
    required this.id,
    required this.label,
    required this.hostId,
    required this.localPort,
    this.remoteHost = '127.0.0.1',
    required this.remotePort,
  });
  final String id, label, hostId, remoteHost;
  final int localPort, remotePort;
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'hostId': hostId,
    'localPort': localPort,
    'remoteHost': remoteHost,
    'remotePort': remotePort,
  };
  factory ForwardRule.fromJson(Map<String, dynamic> j) => ForwardRule(
    id: j['id'],
    label: j['label'],
    hostId: j['hostId'],
    localPort: j['localPort'],
    remoteHost: j['remoteHost'],
    remotePort: j['remotePort'],
  );
}

class Workspace {
  Workspace({
    List<Host> hosts = const [],
    List<Identity> identities = const [],
    List<Snippet> snippets = const [],
    List<ForwardRule> forwards = const [],
    Map<String, String> knownHosts = const {},
    Map<String, dynamic> settings = const {},
    List<String> history = const [],
  }) : hosts = List.unmodifiable(hosts),
       identities = List.unmodifiable(identities),
       snippets = List.unmodifiable(snippets),
       forwards = List.unmodifiable(forwards),
       knownHosts = Map.unmodifiable(knownHosts),
       settings = Map.unmodifiable(settings),
       history = List.unmodifiable(history);
  final List<Host> hosts;
  final List<Identity> identities;
  final List<Snippet> snippets;
  final List<ForwardRule> forwards;
  final Map<String, String> knownHosts;
  final Map<String, dynamic> settings;
  final List<String> history;
  Workspace copyWith({
    List<Host>? hosts,
    List<Identity>? identities,
    List<Snippet>? snippets,
    List<ForwardRule>? forwards,
    Map<String, String>? knownHosts,
    Map<String, dynamic>? settings,
    List<String>? history,
  }) => Workspace(
    hosts: hosts ?? this.hosts,
    identities: identities ?? this.identities,
    snippets: snippets ?? this.snippets,
    forwards: forwards ?? this.forwards,
    knownHosts: knownHosts ?? this.knownHosts,
    settings: settings ?? this.settings,
    history: history ?? this.history,
  );
  Map<String, dynamic> toJson() => {
    'hosts': hosts.map((v) => v.toJson()).toList(),
    'identities': identities.map((v) => v.toJson()).toList(),
    'snippets': snippets.map((v) => v.toJson()).toList(),
    'forwards': forwards.map((v) => v.toJson()).toList(),
    'knownHosts': knownHosts,
    'settings': settings,
    'history': history,
  };
  factory Workspace.fromJson(Map<String, dynamic> j) => Workspace(
    hosts: (j['hosts'] as List? ?? [])
        .map((v) => Host.fromJson(Map<String, dynamic>.from(v)))
        .toList(),
    identities: (j['identities'] as List? ?? [])
        .map((v) => Identity.fromJson(Map<String, dynamic>.from(v)))
        .toList(),
    snippets: (j['snippets'] as List? ?? [])
        .map((v) => Snippet.fromJson(Map<String, dynamic>.from(v)))
        .toList(),
    forwards: (j['forwards'] as List? ?? [])
        .map((v) => ForwardRule.fromJson(Map<String, dynamic>.from(v)))
        .toList(),
    knownHosts: Map<String, String>.from(j['knownHosts'] ?? {}),
    settings: Map<String, dynamic>.from(j['settings'] ?? {}),
    history: List<String>.from(j['history'] ?? []),
  );
}
