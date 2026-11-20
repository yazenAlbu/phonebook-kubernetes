import os

from flask import Flask, g, render_template, request
from flaskext.mysql import MySQL


app = Flask(__name__)
app.config['MYSQL_DATABASE_HOST'] = os.environ['MYSQL_DATABASE_HOST']
app.config['MYSQL_DATABASE_PASSWORD'] = os.environ['MYSQL_PASSWORD']
app.config['MYSQL_DATABASE_DB'] = os.environ['MYSQL_DATABASE']
app.config['MYSQL_DATABASE_USER'] = os.environ['MYSQL_USER']
mysql = MySQL(app)


def get_db():
    if 'db' not in g:
        g.db = mysql.connect()
        g.db.autocommit(True)
    return g.db


@app.teardown_appcontext
def close_db(error=None):
    connection = g.pop('db', None)
    if connection is not None:
        connection.close()


@app.context_processor
def page_settings():
    return {
        'developer_name': os.getenv('DEVELOPER_NAME', 'Yazen Albu'),
        'management_url': os.getenv('MANAGEMENT_URL', '/'),
    }


def find_persons(keyword):
    with get_db().cursor() as cursor:
        cursor.execute(
            'SELECT * FROM phonebook WHERE name LIKE %s',
            (f'%{keyword.strip().lower()}%',),
        )
        rows = cursor.fetchall()
    persons = [
        {'id': row[0], 'name': row[1].strip().title(), 'number': row[2]}
        for row in rows
    ]
    if not persons:
        persons = [{'name': 'No Result', 'number': 'No Result'}]
    return persons


@app.route('/', methods=['GET', 'POST'])
@app.route('/search', methods=['GET', 'POST'])
@app.route('/search/', methods=['GET', 'POST'])
def find_records():
    if request.method == 'POST':
        keyword = request.form.get('username', '')
        persons = find_persons(keyword)
        return render_template('index.html', persons=persons, keyword=keyword, show_result=True)
    return render_template('index.html', show_result=False)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
