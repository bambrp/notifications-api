import uuid

from sqlalchemy.dialects.postgresql import UUID

from app import db
from app.dao.dao_utils import transactional


class TemplateFolder(db.Model):
    __tablename__ = 'template_folder'

    id = db.Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    service_id = db.Column(UUID(as_uuid=True), db.ForeignKey('services.id'), nullable=False)
    name = db.Column(db.String, nullable=False)
    parent_id = db.Column(UUID(as_uuid=True), db.ForeignKey('template_folder.id'), nullable=True)

    service = db.relationship('Service', backref='all_template_folders')
    parent = db.relationship('TemplateFolder', remote_side=[id], backref='subfolders')

    def serialize(self):
        return {
            'id': self.id,
            'name': self.name,
            'parent_id': self.parent_id,
            'service_id': self.service_id
        }

    @classmethod
    def get_by_id(cls, template_folder_id):
        return cls.query.filter(TemplateFolder.id == template_folder_id).one()

    @transactional
    def persist(self):
        db.session.add(self)

    @classmethod
    @transactional
    def rename(cls, template_folder_id, new_name):
        cls.query.filter_by(id=template_folder_id).update({"name": new_name})
        return cls.get_by_id(template_folder_id)

    @transactional
    def delete(self):
        db.session.delete(self)

    @classmethod
    def get_all_folders_for_service(cls, service_id):
        return cls.query.filter_by(service_id=service_id).all()
