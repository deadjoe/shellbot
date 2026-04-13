#!/usr/bin/env bash
python3 -c "
import sys, ast
try:
    expr = sys.argv[1]
    result = eval(expr, {'__builtins__': {}}, {
        'abs': abs, 'round': round, 'min': min, 'max': max,
        'pow': pow, 'sum': sum, 'int': int, 'float': float,
        'len': len, 'sorted': sorted, 'range': range,
    })
    print(result)
except Exception as e:
    print(f'Error: {e}')
" "$1"
