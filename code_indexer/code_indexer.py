#!/usr/bin/env python3
"""
Code Parser for AST-aware code chunking with Tree-sitter.
Indexes code functions into Qdrant vector database.
"""

import os
import time
import hashlib
import json
import signal
import sys
from pathlib import Path
from typing import Dict, List, Optional, Any

from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from tree_sitter_languages import get_parser
from qdrant_client import QdrantClient
from qdrant_client.http import models
import ollama

class CodeParser:
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.qdrant = QdrantClient(host=config["qdrant_host"], port=config["qdrant_port"])
        self.setup_collection()
        self.parsers = {}
        self.running = True
        self.supported_languages = {
            ".py": "python", ".js": "javascript", ".ts": "typescript",
            ".jsx": "javascript", ".tsx": "typescript", ".java": "java",
            ".go": "go", ".rs": "rust", ".cpp": "cpp", ".c": "c",
            ".rb": "ruby", ".php": "php", ".swift": "swift",
        }
    
    def setup_collection(self):
        try:
            collections = self.qdrant.get_collections().collections
            if not any(c.name == self.config["collection_name"] for c in collections):
                self.qdrant.create_collection(
                    collection_name=self.config["collection_name"],
                    vectors_config=models.VectorParams(
                        size=768,
                        distance=models.Distance.COSINE
                    )
                )
                print(f"Created collection: {self.config['collection_name']}")
        except Exception as e:
            print(f"Collection setup error: {e}")
    
    def get_parser(self, language: str):
        if language not in self.parsers:
            try:
                self.parsers[language] = get_parser(language)
            except Exception as e:
                print(f"Error loading parser for {language}: {e}")
                return None
        return self.parsers[language]
    
    def parse_file(self, file_path: str) -> List[models.PointStruct]:
        ext = os.path.splitext(file_path)[1]
        if ext not in self.supported_languages:
            return []
        
        language = self.supported_languages[ext]
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()
            
            if len(content) < 50:
                return []
            
            # Simple chunking for now
            chunks = [content[i:i+500] for i in range(0, len(content), 500)]
            points = []
            
            for i, chunk in enumerate(chunks):
                embedding = ollama.embeddings(
                    model=self.config["embedding_model"],
                    prompt=chunk[:8000]
                )["embedding"]
                
                point_id = hashlib.md5(f"{file_path}:{i}".encode()).hexdigest()
                
                points.append(models.PointStruct(
                    id=point_id,
                    vector=embedding,
                    payload={
                        "file_path": file_path,
                        "language": language,
                        "chunk": chunk[:500],
                        "chunk_index": i,
                        "last_modified": os.path.getmtime(file_path)
                    }
                ))
            
            return points
        except Exception as e:
            print(f"Error parsing {file_path}: {e}")
            return []
    
    def scan_directory(self, path: str):
        if not os.path.exists(path):
            return
        
        all_points = []
        for root, _, files in os.walk(path):
            for file in files:
                ext = os.path.splitext(file)[1]
                if ext in self.supported_languages:
                    file_path = os.path.join(root, file)
                    points = self.parse_file(file_path)
                    all_points.extend(points)
        
        if all_points:
            for i in range(0, len(all_points), 100):
                batch = all_points[i:i+100]
                self.qdrant.upsert(
                    collection_name=self.config["collection_name"],
                    points=batch
                )
            print(f"Indexed {len(all_points)} chunks")

def main():
    config = {
        "qdrant_host": os.environ.get("QDRANT_HOST", "qdrant"),
        "qdrant_port": int(os.environ.get("QDRANT_PORT", 6333)),
        "ollama_host": os.environ.get("OLLAMA_HOST", "ollama"),
        "ollama_port": int(os.environ.get("OLLAMA_PORT", 11434)),
        "collection_name": os.environ.get("COLLECTION_NAME", "code_ast"),
        "embedding_model": os.environ.get("EMBEDDING_MODEL", "nomic-embed-text"),
        "watch_paths": [p.strip() for p in os.environ.get("WATCH_PATHS", "/code/repos").split(",")],
    }
    
    parser = CodeParser(config)
    
    for path in config["watch_paths"]:
        if os.path.exists(path):
            parser.scan_directory(path)
    
    while parser.running:
        time.sleep(1)

if __name__ == "__main__":
    main()
