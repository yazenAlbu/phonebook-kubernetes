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
        'search_url': os.getenv('SEARCH_URL', '/search'),
        'management_url': os.getenv('MANAGEMENT_URL', '/'),
    }


def init_phonebook_db():
    with get_db().cursor() as cursor:
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS phonebook (
                id INT NOT NULL AUTO_INCREMENT,
                name VARCHAR(100) NOT NULL,
                number VARCHAR(100) NOT NULL,
                PRIMARY KEY (id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ''')


def insert_person(name, number):
    name = name.strip().lower()
    with get_db().cursor() as cursor:
        cursor.execute('SELECT * FROM phonebook WHERE name LIKE %s', (name,))
        row = cursor.fetchone()
        if row is not None:
            return f'Person with name {row[1].title()} already exists.'
        cursor.execute(
            'INSERT INTO phonebook (name, number) VALUES (%s, %s)',
            (name, number),
        )
    return f'Person {name.title()} added to Phonebook successfully'


def update_person(name, number):
    name = name.strip().lower()
    with get_db().cursor() as cursor:
        cursor.execute('SELECT * FROM phonebook WHERE name LIKE %s', (name,))
        row = cursor.fetchone()
        if row is None:
            return f'Person with name {name.title()} does not exist.'
        cursor.execute(
            'UPDATE phonebook SET number = %s WHERE id = %s',
            (number, row[0]),
        )
    return f'Phone record of {name.title()} is updated successfully'


def delete_person(name):
    name = name.strip().lower()
    with get_db().cursor() as cursor:
        cursor.execute('SELECT * FROM phonebook WHERE name LIKE %s', (name,))
        row = cursor.fetchone()
        if row is None:
            return f'Person with name {name.title()} does not exist, no need to delete.'
        cursor.execute('DELETE FROM phonebook WHERE id = %s', (row[0],))
    return f'Phone record of {name.title()} is deleted from the phonebook successfully'


@app.route('/add', methods=['GET', 'POST'])
def add_record():
    if request.method == 'POST':
        name = request.form.get('username', '')
        phone_number = request.form.get('phonenumber', '')
        if not name.strip():
            return render_template(
                'add-update.html',
                not_valid=True,
                message='Invalid input: Name can not be empty',
                show_result=False,
                action_name='save',
            )
        if name.isdecimal():
            return render_template(
                'add-update.html',
                not_valid=True,
                message='Invalid input: Name of person should be text',
                show_result=False,
                action_name='save',
            )
        if not phone_number.strip():
            return render_template(
                'add-update.html',
                not_valid=True,
                message='Invalid input: Phone number can not be empty',
                show_result=False,
                action_name='save',
            )
        if not phone_number.isdecimal():
            return render_template(
                'add-update.html',
                not_valid=True,
                message='Invalid input: Phone number should be in numeric format',
                show_result=False,
                action_name='save',
            )
        result = insert_person(name, phone_number)
        return render_template(
            'add-update.html',
            show_result=True,
            result=result,
            not_valid=False,
            action_name='save',
        )
    return render_template(
        'add-update.html',
        show_result=False,
        not_valid=False,
        action_name='save',
    )


@app.route('/update', methods=['GET', 'POST'])
def update_record():
    if request.method == 'POST':
        name = request.form.get('username', '')
        phone_number = request.form.get('phonenumber', '')
        if not name.strip():
            return render_template(
                'add-update.html',
                not_valid=True,
                message='Invalid input: Name can not be empty',
                show_result=False,
                action_name='update',
            )
        if not phone_number.strip():
            return render_template(
                'add-update.html',
                not_valid=True,
                message='Invalid input: Phone number can not be empty',
                show_result=False,
                action_name='update',
            )
        if not phone_number.isdecimal():
            return render_template(
                'add-update.html',
                not_valid=True,
                message='Invalid input: Phone number should be in numeric format',
                show_result=False,
                action_name='update',
            )
        result = update_person(name, phone_number)
        return render_template(
            'add-update.html',
            show_result=True,
            result=result,
            not_valid=False,
            action_name='update',
        )
    return render_template(
        'add-update.html',
        show_result=False,
        not_valid=False,
        action_name='update',
    )


@app.route('/delete', methods=['GET', 'POST'])
def delete_record():
    if request.method == 'POST':
        name = request.form.get('username', '')
        if not name.strip():
            return render_template(
                'delete.html',
                not_valid=True,
                message='Invalid input: Name can not be empty',
                show_result=False,
            )
        result = delete_person(name)
        return render_template('delete.html', show_result=True, result=result, not_valid=False)
    return render_template('delete.html', show_result=False, not_valid=False)


@app.route('/', methods=['GET', 'POST'])
def find_records():
    return render_template('index.html')


with app.app_context():
    init_phonebook_db()


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
