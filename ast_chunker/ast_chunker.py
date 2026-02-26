#!/usr/bin/env python3
"""Indexes source code chunks into Qdrant using Ollama embeddings."""

import hashlib
import os
import time
from typing import Any, Dict, List

import ollama
from qdrant_client import QdrantClient
from qdrant_client.http import models


class CodeParser:
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.qdrant = QdrantClient(host=config["qdrant_host"], port=config["qdrant_port"])
        self.ollama_client = ollama.Client(host=f"http://{config['ollama_host']}:{config['ollama_port']}")
        self.running = True
        self.supported_languages = {
            ".py": "python",
            ".js": "javascript",
            ".ts": "typescript",
            ".jsx": "javascript",
            ".tsx": "typescript",
            ".java": "java",
            ".go": "go",
            ".rs": "rust",
            ".cpp": "cpp",
            ".c": "c",
            ".rb": "ruby",
            ".php": "php",
            ".swift": "swift",
        }
        self.setup_collection()

    def setup_collection(self):
        collections = self.qdrant.get_collections().collections
        if not any(c.name == self.config["collection_name"] for c in collections):
            self.qdrant.create_collection(
                collection_name=self.config["collection_name"],
                vectors_config=models.VectorParams(size=768, distance=models.Distance.COSINE),
            )
            print(f"Created collection: {self.config['collection_name']}")

    def parse_file(self, file_path: str) -> List[models.PointStruct]:
        ext = os.path.splitext(file_path)[1]
        if ext not in self.supported_languages:
            return []

        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()

        if len(content) < 50:
            return []

        language = self.supported_languages[ext]
        chunks = [content[i : i + 500] for i in range(0, len(content), 500)]
        points: List[models.PointStruct] = []

        for i, chunk in enumerate(chunks):
            embedding = self.ollama_client.embeddings(
                model=self.config["embedding_model"],
                prompt=chunk[:8000],
            )["embedding"]

            point_id = hashlib.md5(f"{file_path}:{i}".encode(), usedforsecurity=False).hexdigest()
            points.append(
                models.PointStruct(
                    id=point_id,
                    vector=embedding,
                    payload={
                        "file_path": file_path,
                        "language": language,
                        "chunk": chunk[:500],
                        "chunk_index": i,
                        "last_modified": os.path.getmtime(file_path),
                    },
                )
            )

        return points

    def scan_directory(self, path: str):
        if not os.path.exists(path):
            return

        all_points: List[models.PointStruct] = []
        for root, _, files in os.walk(path):
            for file in files:
                file_path = os.path.join(root, file)
                try:
                    all_points.extend(self.parse_file(file_path))
                except Exception as exc:
                    print(f"Error parsing {file_path}: {exc}")

        for i in range(0, len(all_points), 100):
            self.qdrant.upsert(
                collection_name=self.config["collection_name"],
                points=all_points[i : i + 100],
            )

        if all_points:
            print(f"Indexed {len(all_points)} chunks from {path}")


def main():
    watch_paths_env = os.environ.get("WATCH_PATHS") or os.environ.get("CODE_PATHS", "/code/repos")
    config = {
        "qdrant_host": os.environ.get("QDRANT_HOST", "qdrant"),
        "qdrant_port": int(os.environ.get("QDRANT_PORT", 6333)),
        "ollama_host": os.environ.get("OLLAMA_HOST", "ollama"),
        "ollama_port": int(os.environ.get("OLLAMA_PORT", 11434)),
        "collection_name": os.environ.get("COLLECTION_NAME", "code_ast"),
        "embedding_model": os.environ.get("EMBEDDING_MODEL", "nomic-embed-text"),
        "watch_paths": [p.strip() for p in watch_paths_env.split(",") if p.strip()],
    }

    parser = CodeParser(config)
    for path in config["watch_paths"]:
        parser.scan_directory(path)

    while parser.running:
        time.sleep(1)


if __name__ == "__main__":
    main()
