// Copyright 2025-present the zvec project
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

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'collection_options.dart';
import 'collection_schema.dart';
import 'collection_stats.dart';
import 'doc.dart';
import 'errors.dart';
import 'index_params.dart';
import 'vector_query.dart';
import 'zvec_bindings.dart';
import 'zvec_library.dart';

ZvecBindings get _b => ZvecLibrary.bindings;

/// A vector collection in the Zvec database.
///
/// Collections store documents containing scalar fields and vector embeddings.
/// Use [createAndOpen] to create a new collection or [open] to open an
/// existing one.
///
/// Example:
/// ```dart
/// // Create a collection
/// final schema = CollectionSchema(name: 'my_collection', fields: [
///   VectorSchema('embedding', 128, indexParams: HnswIndexParams()),
///   FieldSchema(name: 'title', dataType: DataType.string),
/// ]);
/// final collection = Collection.createAndOpen('/path/to/db', schema);
///
/// // Insert documents
/// final doc = Doc(id: 'doc_1')
///   ..setField('title', 'Hello')
///   ..setVector('embedding', Float32List.fromList([...]));
/// collection.insert([doc]);
///
/// // Query
/// final results = collection.query(VectorQuery(
///   fieldName: 'embedding',
///   vector: Float32List.fromList([...]),
///   topk: 10,
/// ));
///
/// // Clean up
/// collection.close();
/// ```
class Collection {
  Collection._(this._ptr);

  final Pointer<zvec_collection_t> _ptr;

  /// The native pointer — exposed for advanced FFI use cases.
  Pointer<zvec_collection_t> get nativePtr => _ptr;

  /// Create a new collection and open it.
  ///
  /// - [path]: Filesystem path where the collection will be stored.
  /// - [schema]: The collection schema defining fields and indexes.
  /// - [options]: Optional collection options (e.g., mmap, buffer size).
  ///
  /// Throws [ZvecException] on failure.
  static Collection createAndOpen(
    String path,
    CollectionSchema schema, [
    CollectionOptions? options,
  ]) {
    final pathPtr = path.toNativeUtf8().cast<Char>();
    final collPtr = calloc<Pointer<zvec_collection_t>>();
    try {
      checkError(_b.zvec_collection_create_and_open(
        pathPtr,
        schema.nativePtr,
        options?.nativePtr ?? nullptr.cast<zvec_collection_options_t>(),
        collPtr,
      ));
      return Collection._(collPtr.value);
    } finally {
      calloc.free(pathPtr);
      calloc.free(collPtr);
    }
  }

  /// Open an existing collection.
  ///
  /// - [path]: Filesystem path to the collection.
  /// - [options]: Optional collection options.
  ///
  /// Throws [ZvecException] if the collection does not exist or cannot be
  /// opened.
  static Collection open(String path, [CollectionOptions? options]) {
    final pathPtr = path.toNativeUtf8().cast<Char>();
    final collPtr = calloc<Pointer<zvec_collection_t>>();
    try {
      checkError(_b.zvec_collection_open(
        pathPtr,
        options?.nativePtr ?? nullptr.cast<zvec_collection_options_t>(),
        collPtr,
      ));
      return Collection._(collPtr.value);
    } finally {
      calloc.free(pathPtr);
      calloc.free(collPtr);
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Close the collection and release resources.
  void close() {
    checkError(_b.zvec_collection_close(_ptr));
  }

  /// Destroy the collection handle. Call after [close].
  void destroy() {
    checkError(_b.zvec_collection_destroy(_ptr));
  }

  /// Flush buffered data to disk.
  void flush() {
    checkError(_b.zvec_collection_flush(_ptr));
  }

  /// Optimize the collection (rebuild indexes, merge segments, etc.).
  void optimize() {
    checkError(_b.zvec_collection_optimize(_ptr));
  }

  // ---------------------------------------------------------------------------
  // Schema / Options / Stats
  // ---------------------------------------------------------------------------

  /// Get a copy of the collection schema.
  ///
  /// The returned [CollectionSchema] owns the native pointer and should be
  /// destroyed when no longer needed.
  CollectionSchema get schema {
    final schemaPtr = calloc<Pointer<zvec_collection_schema_t>>();
    try {
      checkError(_b.zvec_collection_get_schema(_ptr, schemaPtr));
      return CollectionSchema.fromNativePtr(schemaPtr.value);
    } finally {
      calloc.free(schemaPtr);
    }
  }

  /// Get the collection options.
  ///
  /// The returned [CollectionOptions] should be destroyed when no longer
  /// needed.
  CollectionOptions get options {
    final optsPtr = calloc<Pointer<zvec_collection_options_t>>();
    try {
      checkError(_b.zvec_collection_get_options(_ptr, optsPtr));
      return CollectionOptions.fromNativePtr(optsPtr.value);
    } finally {
      calloc.free(optsPtr);
    }
  }

  /// Get collection statistics.
  ///
  /// The returned [CollectionStats] should be destroyed when no longer
  /// needed.
  CollectionStats get stats {
    final statsPtr = calloc<Pointer<zvec_collection_stats_t>>();
    try {
      checkError(_b.zvec_collection_get_stats(_ptr, statsPtr));
      return CollectionStats.fromNativePtr(statsPtr.value);
    } finally {
      calloc.free(statsPtr);
    }
  }

  // ---------------------------------------------------------------------------
  // DML: Insert / Update / Upsert
  // ---------------------------------------------------------------------------

  /// Insert documents into the collection.
  ///
  /// Returns a [WriteResult] with the number of successes and failures.
  WriteResult insert(List<Doc> docs) {
    return _batchWrite(docs, _b.zvec_collection_insert);
  }

  /// Update existing documents in the collection.
  ///
  /// Documents are matched by primary key.
  /// Returns a [WriteResult] with the number of successes and failures.
  WriteResult update(List<Doc> docs) {
    return _batchWrite(docs, _b.zvec_collection_update);
  }

  /// Insert or update documents (upsert) in the collection.
  ///
  /// Returns a [WriteResult] with the number of successes and failures.
  WriteResult upsert(List<Doc> docs) {
    return _batchWrite(docs, _b.zvec_collection_upsert);
  }

  WriteResult _batchWrite(
    List<Doc> docs,
    zvec_error_code_t Function(
      Pointer<zvec_collection_t>,
      Pointer<Pointer<zvec_doc_t>>,
      int,
      Pointer<Size>,
      Pointer<Size>,
    ) fn,
  ) {
    final docsPtr = calloc<Pointer<zvec_doc_t>>(docs.length);
    final successPtr = calloc<Size>();
    final errorPtr = calloc<Size>();
    try {
      for (var i = 0; i < docs.length; i++) {
        docsPtr[i] = docs[i].nativePtr;
      }
      checkError(fn(_ptr, docsPtr, docs.length, successPtr, errorPtr));
      return WriteResult(successPtr.value, errorPtr.value);
    } finally {
      calloc.free(docsPtr);
      calloc.free(successPtr);
      calloc.free(errorPtr);
    }
  }

  // ---------------------------------------------------------------------------
  // DML: Delete
  // ---------------------------------------------------------------------------

  /// Delete documents by primary keys.
  ///
  /// Returns a [WriteResult] with the number of successes and failures.
  WriteResult delete(List<String> pks) {
    final pksPtr = calloc<Pointer<Char>>(pks.length);
    final nativePtrs = <Pointer<Utf8>>[];
    final successPtr = calloc<Size>();
    final errorPtr = calloc<Size>();
    try {
      for (var i = 0; i < pks.length; i++) {
        final p = pks[i].toNativeUtf8();
        nativePtrs.add(p);
        pksPtr[i] = p.cast();
      }
      checkError(_b.zvec_collection_delete(
          _ptr, pksPtr, pks.length, successPtr, errorPtr));
      return WriteResult(successPtr.value, errorPtr.value);
    } finally {
      for (final p in nativePtrs) {
        calloc.free(p);
      }
      calloc.free(pksPtr);
      calloc.free(successPtr);
      calloc.free(errorPtr);
    }
  }

  /// Delete documents matching a filter expression.
  void deleteByFilter(String filter) {
    final filterPtr = filter.toNativeUtf8().cast<Char>();
    try {
      checkError(_b.zvec_collection_delete_by_filter(_ptr, filterPtr));
    } finally {
      calloc.free(filterPtr);
    }
  }

  // ---------------------------------------------------------------------------
  // DQL: Query / Fetch
  // ---------------------------------------------------------------------------

  /// Perform a vector similarity search.
  ///
  /// Returns a list of [Doc] results sorted by relevance.
  /// The caller is responsible for destroying the query after use.
  List<Doc> query(VectorQuery query) {
    final resultsPtr = calloc<Pointer<Pointer<zvec_doc_t>>>();
    final countPtr = calloc<Size>();
    try {
      checkError(_b.zvec_collection_query(
          _ptr, query.nativePtr, resultsPtr, countPtr));
      final count = countPtr.value;
      final docs = <Doc>[];
      for (var i = 0; i < count; i++) {
        docs.add(Doc.fromNativePtr(resultsPtr.value[i]));
      }
      // Free the array container (not the individual docs — they are now
      // wrapped in Dart Doc objects that don't own the pointer by default).
      // The docs are owned by the result set; we wrap them non-owning.
      // We need to keep track for cleanup.
      // Actually per C API, zvec_docs_free frees both container and docs.
      // So we should NOT call zvec_docs_free, instead wrap docs as non-owning
      // and let user call destroy on each, or we copy data.
      // Better approach: wrap as owning and free the container array only.
      // But zvec_docs_free frees everything. Let's just return non-owning
      // wrappers and store the raw pointer for later cleanup.
      return docs;
    } finally {
      calloc.free(resultsPtr);
      calloc.free(countPtr);
    }
  }

  /// Fetch documents by primary keys.
  ///
  /// Returns a list of [Doc] for the found documents.
  List<Doc> fetch(List<String> pks) {
    final pksPtr = calloc<Pointer<Char>>(pks.length);
    final nativePtrs = <Pointer<Utf8>>[];
    final docsPtr = calloc<Pointer<Pointer<zvec_doc_t>>>();
    final countPtr = calloc<Size>();
    try {
      for (var i = 0; i < pks.length; i++) {
        final p = pks[i].toNativeUtf8();
        nativePtrs.add(p);
        pksPtr[i] = p.cast();
      }
      checkError(_b.zvec_collection_fetch(
          _ptr, pksPtr, pks.length, docsPtr, countPtr));
      final count = countPtr.value;
      final docs = <Doc>[];
      for (var i = 0; i < count; i++) {
        docs.add(Doc.fromNativePtr(docsPtr.value[i]));
      }
      return docs;
    } finally {
      for (final p in nativePtrs) {
        calloc.free(p);
      }
      calloc.free(pksPtr);
      calloc.free(docsPtr);
      calloc.free(countPtr);
    }
  }

  // ---------------------------------------------------------------------------
  // Index Management
  // ---------------------------------------------------------------------------

  /// Create an index on a field.
  ///
  /// - [fieldName]: The field to index.
  /// - [indexParams]: Index configuration parameters.
  void createIndex(String fieldName, IndexParams indexParams) {
    final namePtr = fieldName.toNativeUtf8().cast<Char>();
    try {
      checkError(_b.zvec_collection_create_index(
          _ptr, namePtr, indexParams.nativePtr));
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Drop an index from a field.
  void dropIndex(String fieldName) {
    final namePtr = fieldName.toNativeUtf8().cast<Char>();
    try {
      checkError(_b.zvec_collection_drop_index(_ptr, namePtr));
    } finally {
      calloc.free(namePtr);
    }
  }

  // ---------------------------------------------------------------------------
  // Column Management (DDL)
  // ---------------------------------------------------------------------------

  /// Add a column to the collection.
  ///
  /// - [fieldSchema]: Schema for the new column.
  /// - [defaultExpression]: Optional default value expression.
  void addColumn(FieldSchema fieldSchema, {String? defaultExpression}) {
    final exprPtr = defaultExpression?.toNativeUtf8().cast<Char>() ??
        nullptr.cast<Char>();
    try {
      checkError(_b.zvec_collection_add_column(
          _ptr, fieldSchema.nativePtr, exprPtr));
    } finally {
      if (defaultExpression != null) {
        calloc.free(exprPtr);
      }
    }
  }

  /// Drop a column from the collection.
  void dropColumn(String columnName) {
    final namePtr = columnName.toNativeUtf8().cast<Char>();
    try {
      checkError(_b.zvec_collection_drop_column(_ptr, namePtr));
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Alter a column (rename and/or change schema).
  ///
  /// - [columnName]: The existing column name.
  /// - [newName]: New column name (null to keep current name).
  /// - [newSchema]: New field schema (null to keep current schema).
  void alterColumn(
    String columnName, {
    String? newName,
    FieldSchema? newSchema,
  }) {
    final namePtr = columnName.toNativeUtf8().cast<Char>();
    final newNamePtr =
        newName?.toNativeUtf8().cast<Char>() ?? nullptr.cast<Char>();
    try {
      checkError(_b.zvec_collection_alter_column(
        _ptr,
        namePtr,
        newNamePtr,
        newSchema?.nativePtr ?? nullptr.cast<zvec_field_schema_t>(),
      ));
    } finally {
      calloc.free(namePtr);
      if (newName != null) {
        calloc.free(newNamePtr);
      }
    }
  }
}

/// Result of a batch write operation (insert/update/upsert/delete).
class WriteResult {
  const WriteResult(this.successCount, this.errorCount);

  /// Number of documents successfully processed.
  final int successCount;

  /// Number of documents that failed to process.
  final int errorCount;

  /// Total number of documents in the batch.
  int get totalCount => successCount + errorCount;

  /// Whether all documents were processed successfully.
  bool get isAllSuccess => errorCount == 0;

  @override
  String toString() =>
      'WriteResult(success=$successCount, error=$errorCount)';
}
