from flask import Blueprint, jsonify, request
from sqlalchemy.exc import IntegrityError

from app.errors import register_errors
from app.models.template_folder import TemplateFolder
from app.template_folder.template_folder_schema import (
    post_create_template_folder_schema,
    post_rename_template_folder_schema
)
from app.schema_validation import validate

template_folder_blueprint = Blueprint(
    'template_folder',
    __name__,
    url_prefix='/service/<uuid:service_id>/template-folder'
)
register_errors(template_folder_blueprint)


@template_folder_blueprint.errorhandler(IntegrityError)
def handle_integrity_error(exc):
    if 'template_folder_parent_id_fkey' in str(exc):
        return jsonify(result='error', message='parent_id not found'), 400

    raise


@template_folder_blueprint.route('', methods=['GET'])
def get_template_folders_for_service(service_id):
    template_folders = [o.serialize() for o in TemplateFolder.get_all_folders_for_service(service_id)]
    return jsonify(template_folders=template_folders)


@template_folder_blueprint.route('', methods=['POST'])
def create_template_folder(service_id):
    data = request.get_json()

    validate(data, post_create_template_folder_schema)

    template_folder = TemplateFolder(
        service_id=service_id,
        name=data['name'].strip(),
        parent_id=data['parent_id']
    )

    template_folder.persist()

    return jsonify(data=template_folder.serialize()), 201


@template_folder_blueprint.route('/<uuid:template_folder_id>/rename', methods=['POST'])
def rename_template_folder(service_id, template_folder_id):
    data = request.get_json()

    validate(data, post_rename_template_folder_schema)

    template_folder = TemplateFolder.rename(template_folder_id=template_folder_id, new_name=data['name'])

    return jsonify(data=template_folder.serialize()), 200


@template_folder_blueprint.route('/<uuid:template_folder_id>', methods=['DELETE'])
def delete_template_folder(service_id, template_folder_id):
    template_folder = TemplateFolder.get_by_id(template_folder_id)

    # don't allow deleting if there's anything in the folder (even if it's just more empty subfolders)
    if template_folder.subfolders or template_folder.templates:
        return jsonify(result='error', message='Folder is not empty'), 400

    template_folder.delete()

    return '', 204
