import os
import re

def read_functions_file(filename):
    with open(filename, 'r') as f:
        return [line.strip() for line in f]

def parse_function_info(line):
    parts = line.split(':')
    if len(parts) != 2:
        return None, None
    filename, function_def = parts
    match = re.search(r'function\s+(\w+\.\w+)', function_def)
    if not match:
        return None, None
    return filename, match.group(1)

def check_function_in_file(filename, function_name):
    if not os.path.exists(filename):
        return False
    with open(filename, 'r') as f:
        content = f.read()
        pattern = rf'function\s+{re.escape(function_name)}\s*\('
        return re.search(pattern, content) is not None

def main():
    functions_file = 'tests/functions.txt'
    functions_list = read_functions_file(functions_file)

    results = []
    for line in functions_list:
        filename, function_name = parse_function_info(line)
        if filename and function_name:
            exists = check_function_in_file(filename, function_name)
            results.append((filename, function_name, exists))

    print("Function Validation Results:")
    print("-----------------------------")
    for filename, function_name, exists in results:
        status = "Found" if exists else "Not found"
        print(f"{filename}: {function_name} - {status}")

    missing_functions = [f"{filename}: {function_name}" for filename, function_name, exists in results if not exists]
    if missing_functions:
        print("\nMissing functions:")
        for func in missing_functions:
            print(func)
    else:
        print("\nAll functions were found in their respective files.")

if __name__ == "__main__":
    main()