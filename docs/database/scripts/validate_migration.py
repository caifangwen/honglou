#!/usr/bin/env python3
"""
《红楼回忆志》数据一致性验证自动化脚本
依赖：psycopg2, tabulate
用法：python validate_migration.py
"""

import os
import sys
import json
import psycopg2
from datetime import datetime
from typing import Dict, List, Tuple
from tabulate import tabulate

# 配置
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': os.getenv('DB_PORT', '5432'),
    'database': os.getenv('DB_NAME', 'honglou_db'),
    'user': os.getenv('DB_USER', 'postgres'),
    'password': os.getenv('DB_PASSWORD', '')
}

VALIDATION_QUERIES = {
    'level1_count': """
        SELECT 
            'players' AS table_name,
            (SELECT COUNT(*) FROM public.players) AS source_count,
            (SELECT COUNT(*) FROM public.player_role_stats) AS target_count,
            CASE 
                WHEN (SELECT COUNT(*) FROM public.players) = 
                     (SELECT COUNT(*) FROM public.player_role_stats) 
                THEN '✅ PASS' ELSE '❌ FAIL' 
            END AS status
        UNION ALL
        SELECT 
            'rumors',
            (SELECT COUNT(*) FROM public.messages WHERE message_type='rumor'),
            (SELECT COUNT(*) FROM public.rumors),
            CASE 
                WHEN (SELECT COUNT(*) FROM public.messages WHERE message_type='rumor') = 
                     (SELECT COUNT(*) FROM public.rumors) 
                THEN '✅ PASS' ELSE '❌ FAIL' 
            END
    """,
    'level4_foreign_keys': """
        SELECT 
            'players_exist_in_stats' AS check_name,
            CASE 
                WHEN NOT EXISTS (
                    SELECT 1 FROM public.player_role_stats s
                    LEFT JOIN public.players p ON s.player_id = p.id WHERE p.id IS NULL
                ) THEN '✅ PASS' ELSE '❌ FAIL' 
            END AS status
    """,
    'level4_amounts': """
        SELECT 
            'silver_sum' AS check_name,
            (SELECT SUM(silver) FROM public.players) AS source_total,
            (SELECT SUM(silver) FROM public.player_role_stats) AS target_total,
            CASE 
                WHEN (SELECT SUM(silver) FROM public.players) = 
                     (SELECT SUM(silver) FROM public.player_role_stats) 
                THEN '✅ PASS' ELSE '❌ FAIL' 
            END AS status
    """
}


class DataValidationRunner:
    def __init__(self, db_config: Dict):
        self.db_config = db_config
        self.conn = None
        self.results = {}
        self.failures = []
        
    def connect(self):
        try:
            self.conn = psycopg2.connect(**self.db_config)
            print(f"✅ 数据库连接成功：{self.db_config['host']}")
            return True
        except Exception as e:
            print(f"❌ 数据库连接失败：{e}")
            return False
    
    def disconnect(self):
        if self.conn:
            self.conn.close()
            print("数据库连接已关闭")
    
    def run_query(self, name: str, query: str) -> List[Dict]:
        try:
            with self.conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(query)
                results = [dict(row) for row in cur.fetchall()]
                self.results[name] = results
                print(f"✅ {name}: 执行成功 ({len(results)} 行)")
                return results
        except Exception as e:
            print(f"❌ {name}: 执行失败 - {e}")
            self.failures.append({'name': name, 'error': str(e)})
            return []
    
    def run_all_validations(self):
        print("\n" + "="*60)
        print("开始数据一致性验证")
        print("="*60 + "\n")
        
        for name, query in VALIDATION_QUERIES.items():
            self.run_query(name, query)
    
    def generate_report(self, output_file: str = 'validation_report.md') -> bool:
        report = []
        report.append("# 《红楼回忆志》数据一致性验证报告\n")
        report.append(f"**生成时间**: {datetime.now().isoformat()}\n")
        report.append(f"**数据库**: {self.db_config['database']}@{self.db_config['host']}\n")
        report.append("---\n\n")
        
        total_passed = 0
        total_failed = 0
        
        report.append("## 验证摘要\n\n")
        for name, results in self.results.items():
            if results:
                for row in results:
                    status = row.get('status', '')
                    if '✅' in status or 'PASS' in status:
                        total_passed += 1
                    elif '❌' in status or 'FAIL' in status:
                        total_failed += 1
        
        report.append(f"**总计**: {total_passed} 通过，{total_failed} 失败\n\n")
        
        for name, results in self.results.items():
            if results:
                report.append(f"\n### {name}\n\n")
                headers = list(results[0].keys())
                rows = [[row.get(h, '') for h in headers] for row in results]
                report.append(tabulate(rows, headers=headers, tablefmt='github'))
                report.append("\n")
        
        if self.failures:
            report.append("\n## 执行失败\n\n")
            for failure in self.failures:
                report.append(f"- **{failure['name']}**: {failure['error']}\n")
        
        report.append("\n## 结论\n\n")
        if total_failed == 0:
            report.append("### ✅ 验证通过\n\n所有检查项均通过，数据一致性验证成功。\n")
        else:
            report.append(f"### ❌ 验证失败\n\n共 {total_failed} 项检查失败。\n")
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.writelines(report)
        
        print(f"\n📄 报告已生成：{output_file}")
        return total_failed == 0


def main():
    runner = DataValidationRunner(DB_CONFIG)
    
    if not runner.connect():
        sys.exit(1)
    
    try:
        runner.run_all_validations()
        success = runner.generate_report()
        
        if success:
            print("\n✅ 所有验证通过!")
            sys.exit(0)
        else:
            print("\n❌ 存在验证失败项!")
            sys.exit(1)
    
    finally:
        runner.disconnect()


if __name__ == '__main__':
    main()
