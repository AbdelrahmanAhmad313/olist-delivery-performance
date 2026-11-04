import pandas as pd 
from pathlib import Path 


PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent

RAW_DATA_PATH = PROJECT_ROOT / "data" / "raw"

files = list(RAW_DATA_PATH.glob("*.csv"))

filenames = [
    file.stem.replace("_", " ")
    .removesuffix("dataset")
    .removeprefix("olist")
    .removeprefix("product")
    .strip()
    .replace(" ", "_")
    for file in files
]

files_old_names = [file.name for file in files]


files=dict(zip(filenames,files_old_names))

data = {}

for name, filename in files.items():
    data[name] = pd.read_csv(RAW_DATA_PATH / filename)
    
for name in files:
    # print(data[name].shape)
    print(data[name].columns)
    # print(data[name].dtypes)
    