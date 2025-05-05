import 'package:renpy_parser/src/models/renpy_statement.dart';

/// Represents a complete RenPy script.
class RenPyScript {
  final List<RenPyStatement> statements;

  RenPyScript(this.statements);

  /// Find all labels in the script.
  Map<String, RenPyLabelStatement> get labels {
    final result = <String, RenPyLabelStatement>{};

    void findLabels(List<RenPyStatement> stmts) {
      for (final stmt in stmts) {
        if (stmt is RenPyLabelStatement) {
          result[stmt.name] = stmt;
          findLabels(stmt.block);
        } else if (stmt is RenPyBlockStatement) {
          findLabels(stmt.block);
        }
      }
    }

    findLabels(statements);
    return result;
  }

  /// Find all character definitions in the script.
  Map<String, String> get characters {
    final result = <String, String>{};

    // Fixed: Search recursively through all blocks to find character definitions.
    void findCharacters(List<RenPyStatement> stmts) {
      for (final stmt in stmts) {
        if (stmt is RenPyDefineStatement) {
          // Look for Character class usage.
          if (stmt.expression.contains('Character(') ||
              stmt.expression.contains('Character (')) {
            result[stmt.name] = stmt.expression;
          }
        } else if (stmt is RenPyPythonStatement) {
          // crude but effective:  `$ e = Character(`…
          final pyMatch = RegExp(
            r'''\$\s*([a-zA-Z_]\w*)\s*=\s*Character\s*\(''',
          ).firstMatch(stmt.code);
          if (pyMatch != null) {
            final name = pyMatch.group(1)!;
            result[name] = stmt.code;
          }
        }

        // Search in blocks too.
        if (stmt is RenPyBlockStatement) {
          findCharacters(stmt.block);
        }
      }
    }

    findCharacters(statements);
    return result;
  }

  /// Find the first label with the given name.
  RenPyLabelStatement? findLabel(String name) {
    return labels[name];
  }

  /// Find statements that match a predicate.
  List<T> findStatements<T extends RenPyStatement>(bool Function(T) predicate) {
    final result = <T>[];

    void searchStatements(List<RenPyStatement> stmts) {
      for (final stmt in stmts) {
        if (stmt is T && predicate(stmt)) {
          result.add(stmt);
        }

        if (stmt is RenPyBlockStatement) {
          searchStatements(stmt.block);
            } else if (stmt is RenPyMenuStatement) {
          // Recurse into every choice’s block so nested menus, play-sound lines,
          // etc. are discoverable.
          for (final choice in stmt.items) {
            searchStatements(choice.block);
          }
        }
      }
    }

    searchStatements(statements);
    return result;
  }
}
